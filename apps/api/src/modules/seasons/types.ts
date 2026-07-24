export type Season = {
  id: number;
  organizationId: number;
  organizationName: string;
  name: string;
  startDate: string | null;
  endDate: string | null;
  active: boolean;
  createdAt: string | Date;
  updatedAt: string | Date;
};
