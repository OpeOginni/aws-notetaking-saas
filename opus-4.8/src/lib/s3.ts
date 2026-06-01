import {
  S3Client,
  PutObjectCommand,
  GetObjectCommand,
  DeleteObjectCommand,
} from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

const region = process.env.AWS_REGION || "eu-central-1";
const bucket = process.env.S3_BUCKET;

if (!bucket) {
  // Defer hard failure to call sites so the build/import doesn't crash, but warn.
  console.warn("[s3] S3_BUCKET env var is not set");
}

// In ECS the SDK picks up credentials from the task role automatically.
// Locally it uses the standard credential chain (env vars / profile).
export const s3 = new S3Client({ region });

export function getBucket(): string {
  if (!bucket) throw new Error("S3_BUCKET environment variable is not set");
  return bucket;
}

export async function uploadObject(
  key: string,
  body: Buffer,
  contentType: string
): Promise<void> {
  await s3.send(
    new PutObjectCommand({
      Bucket: getBucket(),
      Key: key,
      Body: body,
      ContentType: contentType,
    })
  );
}

export async function getObjectStream(key: string) {
  const res = await s3.send(
    new GetObjectCommand({ Bucket: getBucket(), Key: key })
  );
  return res;
}

export async function deleteObject(key: string): Promise<void> {
  await s3.send(
    new DeleteObjectCommand({ Bucket: getBucket(), Key: key })
  );
}

export async function getPresignedDownloadUrl(
  key: string,
  expiresIn = 3600
): Promise<string> {
  return getSignedUrl(
    s3,
    new GetObjectCommand({ Bucket: getBucket(), Key: key }),
    { expiresIn }
  );
}
