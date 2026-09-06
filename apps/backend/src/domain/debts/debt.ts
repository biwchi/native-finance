export type DebtDetails = { name: string; icon?: string; color?: string };
export type Debt = DebtDetails & { id: string };

export interface DebtRepository {
  list(): Promise<Debt[]>;
  findById(id: string): Promise<Debt | null>;
  create(details: DebtDetails): Promise<Debt>;
  update(id: string, details: Partial<DebtDetails>): Promise<Debt | null>;
}
