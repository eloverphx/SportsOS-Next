import { z } from "zod";

const optionalDate = z.preprocess(
  (value) => (value === "" || value === undefined ? null : value),
  z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/, "Use YYYY-MM-DD")
    .nullable(),
);

export const seasonInputSchema = z
  .object({
    organizationId: z.coerce.number().int().positive(),
    name: z.string().trim().min(2).max(100),
    startDate: optionalDate.default(null),
    endDate: optionalDate.default(null),
    active: z.coerce.boolean().default(true),
  })
  .superRefine((value, context) => {
    if (value.startDate && value.endDate && value.endDate < value.startDate) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["endDate"],
        message: "End date must be on or after the start date",
      });
    }
  });

export type SeasonInput = z.infer<typeof seasonInputSchema>;
