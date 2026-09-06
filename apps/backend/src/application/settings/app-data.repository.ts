/** The current backend owns one personal workspace; there is no user identity yet. */
export interface AppDataRepository {
  deleteAll(): Promise<void>;
}
