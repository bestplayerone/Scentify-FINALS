const { randomUUID } = require('node:crypto');

function clone(value) {
  if (value instanceof Date) return new Date(value.getTime());
  if (Array.isArray(value)) return value.map(clone);
  if (value && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [key, clone(entry)]));
  }
  return value;
}

function resolve(value, previous) {
  if (typeof value?.methodName === 'string') {
    if (value.methodName.endsWith('.increment')) return (previous || 0) + value.operand;
    if (value.methodName.endsWith('.serverTimestamp')) return new Date();
  }
  if (Array.isArray(value)) return value.map((entry, index) => resolve(entry, previous?.[index]));
  if (value && Object.getPrototypeOf(value) === Object.prototype) {
    return Object.fromEntries(Object.entries(value).map(([key, entry]) => [
      key,
      resolve(entry, previous?.[key]),
    ]));
  }
  return clone(value);
}

function createFakeFirestore(firestore) {
  const documents = new Map();
  let transactionTail = Promise.resolve();

  class Snapshot {
    constructor(reference) {
      this.ref = reference;
      this.id = reference.id;
      this.exists = documents.has(reference.path);
      this._data = clone(documents.get(reference.path));
    }

    data() {
      return clone(this._data);
    }
  }

  class DocumentReference {
    constructor(path) {
      this.path = path;
      this.id = path.split('/').at(-1);
    }

    collection(name) {
      return new CollectionReference(`${this.path}/${name}`);
    }

    async get() {
      return new Snapshot(this);
    }

    async set(value, options = {}) {
      const previous = documents.get(this.path);
      documents.set(
        this.path,
        options.merge && previous
          ? { ...clone(previous), ...resolve(value, previous) }
          : resolve(value, previous),
      );
    }

    async create(value) {
      if (documents.has(this.path)) throw new Error(`Document already exists: ${this.path}`);
      documents.set(this.path, resolve(value));
    }

    async update(value) {
      if (!documents.has(this.path)) throw new Error(`Document does not exist: ${this.path}`);
      const previous = clone(documents.get(this.path));
      documents.set(this.path, { ...previous, ...resolve(value, previous) });
    }

    async delete() {
      documents.delete(this.path);
    }
  }

  class Query {
    constructor(collectionPath, filters = [], maxResults = Infinity, orderings = [], cursor = null) {
      this.collectionPath = collectionPath;
      this.filters = filters;
      this.maxResults = maxResults;
      this.orderings = orderings;
      this.cursor = cursor;
    }

    where(field, operator, value) {
      return new Query(
        this.collectionPath,
        [...this.filters, [field, operator, value]],
        this.maxResults,
        this.orderings,
        this.cursor,
      );
    }

    limit(count) {
      return new Query(this.collectionPath, this.filters, count, this.orderings, this.cursor);
    }

    orderBy(field, direction = 'asc') {
      return new Query(
        this.collectionPath,
        this.filters,
        this.maxResults,
        [...this.orderings, [field, direction]],
        this.cursor,
      );
    }

    startAfter(value) {
      return new Query(
        this.collectionPath,
        this.filters,
        this.maxResults,
        this.orderings,
        value,
      );
    }

    async get() {
      const prefix = `${this.collectionPath}/`;
      let entries = [...documents.entries()]
        .filter(([path]) => path.startsWith(prefix) && !path.slice(prefix.length).includes('/'))
        .map(([path]) => new Snapshot(new DocumentReference(path)))
        .filter((snapshot) => this.filters.every(([field, operator, value]) => {
          const actual = snapshot.data()?.[field];
          if (operator === '>=') return actual >= value;
          if (operator === '<=') return actual <= value;
          if (operator === '==') return actual === value;
          return false;
        }));
      for (const [field, direction] of this.orderings.toReversed()) {
        entries.sort((left, right) => {
          const leftValue = left.data()?.[field];
          const rightValue = right.data()?.[field];
          const leftTime = leftValue instanceof Date ? leftValue.getTime() : leftValue;
          const rightTime = rightValue instanceof Date ? rightValue.getTime() : rightValue;
          const result = leftTime < rightTime ? -1 : leftTime > rightTime ? 1 : 0;
          return direction === 'desc' ? -result : result;
        });
      }
      if (this.cursor != null && this.orderings.length > 0) {
        const [field, direction] = this.orderings[0];
        const cursorTime = this.cursor instanceof Date ? this.cursor.getTime() : this.cursor;
        entries = entries.filter((snapshot) => {
          const value = snapshot.data()?.[field];
          const valueTime = value instanceof Date ? value.getTime() : value;
          return direction === 'desc' ? valueTime < cursorTime : valueTime > cursorTime;
        });
      }
      const docs = entries.slice(0, this.maxResults);
      return { docs, empty: docs.length === 0, size: docs.length };
    }
  }

  class CollectionReference extends Query {
    constructor(path) {
      super(path);
      this.path = path;
    }

    doc(id) {
      return new DocumentReference(`${this.path}/${id ?? randomUUID()}`);
    }
  }

  firestore.collection = (path) => new CollectionReference(path);
  firestore.runTransaction = async (callback) => {
    const previous = transactionTail;
    let release;
    transactionTail = new Promise((resolve) => { release = resolve; });
    await previous;
    const writes = [];
    const transaction = {
      get: async (reference) => new Snapshot(reference),
      set: (reference, value, options = {}) => writes.push({ type: 'set', reference, value, options }),
      create: (reference, value) => writes.push({ type: 'create', reference, value }),
      update: (reference, value) => writes.push({ type: 'update', reference, value }),
      delete: (reference) => writes.push({ type: 'delete', reference }),
    };
    try {
      const result = await callback(transaction);
      for (const write of writes) {
        if (write.type === 'set') await write.reference.set(write.value, write.options);
        if (write.type === 'create') await write.reference.create(write.value);
        if (write.type === 'update') await write.reference.update(write.value);
        if (write.type === 'delete') await write.reference.delete();
      }
      return result;
    } finally {
      release();
    }
  };

  return { documents };
}

module.exports = { createFakeFirestore };
