import { S3Client } from "@aws-sdk/client-s3";

const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || "eu-central-1";

export const s3Client = new S3Client({ region });

export function getUploadsBucket() {
  if (!process.env.S3_BUCKET_NAME) {
    throw new Error("S3_BUCKET_NAME is required");
  }
  return process.env.S3_BUCKET_NAME;
}
