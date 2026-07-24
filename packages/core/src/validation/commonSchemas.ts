import { z } from "zod";

export const uuidSchema = z
  .string()
  .uuid("A valid UUID is required.");

export const optionalUuidSchema = uuidSchema.optional();

export const emailSchema = z
  .string()
  .trim()
  .email("A valid email address is required.")
  .transform((value) => value.toLowerCase());

export const isoDateTimeSchema = z
  .string()
  .datetime({
    offset: true,
    message: "A valid ISO 8601 date-time with an offset is required."
  });

export const nonEmptyStringSchema = z
  .string()
  .trim()
  .min(1, "A value is required.");

export const positiveIntegerSchema = z
  .number()
  .int("The value must be an integer.")
  .positive("The value must be greater than zero.");

export const nonNegativeIntegerSchema = z
  .number()
  .int("The value must be an integer.")
  .nonnegative("The value cannot be negative.");

export const paginationQuerySchema = z.object({
  page: z.coerce
    .number()
    .int("Page must be an integer.")
    .min(1, "Page must be at least 1.")
    .default(1),

  pageSize: z.coerce
    .number()
    .int("Page size must be an integer.")
    .min(1, "Page size must be at least 1.")
    .max(100, "Page size cannot exceed 100.")
    .default(20)
});

export type PaginationQuery = z.infer<typeof paginationQuerySchema>;