import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";

const required = (name) => {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`Variabile richiesta assente: ${name}`);
  return value;
};

const supabaseUrl = required("SUPABASE_URL").replace(/\/$/, "");
const serviceRoleKey = required("SUPABASE_SERVICE_ROLE_KEY");
const outputRoot = path.resolve(required("STORAGE_BACKUP_DIR"));

const headers = {
  apikey: serviceRoleKey,
  Authorization: `Bearer ${serviceRoleKey}`,
  "Content-Type": "application/json",
};

const request = async (url, init = {}) => {
  const response = await fetch(url, { ...init, headers: { ...headers, ...init.headers } });
  if (!response.ok) {
    const body = (await response.text()).slice(0, 500);
    throw new Error(`Storage API ${response.status}: ${body}`);
  }
  return response;
};

const safeDestination = (bucket, objectName) => {
  const destination = path.resolve(outputRoot, bucket, ...objectName.split("/"));
  const root = path.resolve(outputRoot) + path.sep;
  if (!destination.startsWith(root)) throw new Error("Percorso Storage non sicuro.");
  return destination;
};

const listFolder = async (bucket, prefix = "") => {
  const objects = [];
  for (let offset = 0; ; offset += 1000) {
    const response = await request(
      `${supabaseUrl}/storage/v1/object/list/${encodeURIComponent(bucket)}`,
      {
        method: "POST",
        body: JSON.stringify({
          prefix,
          limit: 1000,
          offset,
          sortBy: { column: "name", order: "asc" },
        }),
      },
    );
    const page = await response.json();
    if (!Array.isArray(page)) throw new Error(`Elenco non valido per il bucket ${bucket}.`);

    for (const entry of page) {
      if (!entry || typeof entry.name !== "string") continue;
      const name = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null && entry.metadata === null) {
        objects.push(...(await listFolder(bucket, name)));
      } else {
        objects.push({
          name,
          id: typeof entry.id === "string" ? entry.id : null,
          updatedAt: typeof entry.updated_at === "string" ? entry.updated_at : null,
          metadata: entry.metadata && typeof entry.metadata === "object" ? entry.metadata : null,
        });
      }
    }
    if (page.length < 1000) break;
  }
  return objects;
};

await mkdir(outputRoot, { recursive: true });
const bucketsResponse = await request(`${supabaseUrl}/storage/v1/bucket`);
const buckets = await bucketsResponse.json();
if (!Array.isArray(buckets)) throw new Error("Elenco bucket non valido.");

const manifest = {
  generatedAt: new Date().toISOString(),
  source: new URL(supabaseUrl).host,
  buckets: [],
};

for (const bucket of buckets) {
  const bucketId = typeof bucket?.id === "string" ? bucket.id : null;
  if (!bucketId) continue;
  const objects = await listFolder(bucketId);
  const bucketManifest = {
    id: bucketId,
    public: bucket.public === true,
    fileSizeLimit: bucket.file_size_limit ?? null,
    allowedMimeTypes: bucket.allowed_mime_types ?? null,
    objects: [],
  };

  for (const object of objects) {
    const encodedPath = object.name.split("/").map(encodeURIComponent).join("/");
    const response = await request(
      `${supabaseUrl}/storage/v1/object/${encodeURIComponent(bucketId)}/${encodedPath}`,
      {},
    );
    const bytes = new Uint8Array(await response.arrayBuffer());
    const destination = safeDestination(bucketId, object.name);
    await mkdir(path.dirname(destination), { recursive: true });
    await writeFile(destination, bytes, { flag: "wx" });
    bucketManifest.objects.push({ ...object, size: bytes.byteLength });
  }
  manifest.buckets.push(bucketManifest);
}

await writeFile(
  path.join(outputRoot, "storage-manifest.json"),
  `${JSON.stringify(manifest, null, 2)}\n`,
  { flag: "wx" },
);

const count = manifest.buckets.reduce((total, bucket) => total + bucket.objects.length, 0);
process.stdout.write(`Storage esportato: ${manifest.buckets.length} bucket, ${count} oggetti.\n`);
