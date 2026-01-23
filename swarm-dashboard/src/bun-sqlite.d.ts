declare module 'bun:sqlite' {
  interface Database {
    close(): void;
    query<T = unknown>(sql: string): QueryResult<T>;
    prepare(sql: string): Statement;
  }

  interface QueryResult<T = unknown> {
    get(...params: unknown[]): T | undefined;
    all(...params: unknown[]): T[];
  }

  interface Statement {
    get(...params: unknown[]): unknown | undefined;
    all(...params: unknown[]): unknown[];
    run(...params: unknown[]): void;
  }

  interface DatabaseOptions {
    readonly?: boolean;
    create?: boolean;
    readwrite?: boolean;
    fileMustExist?: boolean;
  }

  const Database: new (filename: string, options?: DatabaseOptions) => Database;

  export default Database;
}
