#!/usr/bin/env node
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const prod = join(here, "../../simple-docker-caddy/docker-compose.prod.yml");
const out = join(here, "../docker-compose.yml");

const lines = readFileSync(prod, "utf8").split(/\r?\n/);
const outLines = [];
const header = [
  "# Carbon VPS — Docker Compose (prebuilt images only).",
  "# Build ERP/MES/bootstrap locally, push to a registry, set CARBON_IMAGE_* in .env.",
  "# Server: git clone + ./deploy-server.sh (no docker build on the VPS).",
  "#",
  "# Config bind-mounts still need CARBON_REPO (full repo checkout on the host).",
  "",
];

let i = 0;
while (i < lines.length && !lines[i].startsWith("x-shim:")) i++;
outLines.push(...header);

let skipUntilBlank = false;
let inDeploy = false;
let deployIndent = 0;

for (; i < lines.length; i++) {
  const line = lines[i];

  if (
    line.startsWith("x-restart:") ||
    line.startsWith("x-app-deploy:") ||
    line.match(/^x-app-deploy: &/)
  ) {
    skipUntilBlank = true;
    continue;
  }
  if (skipUntilBlank) {
    if (line.trim() === "") skipUntilBlank = false;
    continue;
  }

  if (line.trim() === "deploy: *app-deploy") {
    outLines.push("    restart: unless-stopped");
    continue;
  }

  if (line.trim() === "deploy:") {
    inDeploy = true;
    deployIndent = line.search(/\S/);
    continue;
  }

  if (inDeploy) {
    const indent = line.search(/\S/);
    if (line.trim() === "" || (indent !== -1 && indent <= deployIndent)) {
      inDeploy = false;
      outLines.push("    restart: unless-stopped");
      if (line.trim() !== "") i--;
    }
    continue;
  }

  // Caddy ports block (Swarm host mode) — replace when we hit caddy service ports:
  if (line.trim() === "caddy:" && lines[i + 1]?.includes("image: caddy")) {
    outLines.push("  caddy:");
    i++;
    while (i < lines.length && !lines[i].startsWith("  postgres:")) {
      const l = lines[i];
      if (l.trim().startsWith("ports:")) {
        outLines.push("    ports:");
        outLines.push('      - "80:80"');
        outLines.push('      - "443:443"');
        outLines.push('      - "443:443/udp"');
        while (i < lines.length && lines[i].trim() !== "environment:") i++;
        continue;
      }
      if (l.includes("mode: host") || l.trim().startsWith("- target:")) {
        i++;
        continue;
      }
      if (l.trim().startsWith("deploy:")) {
        while (i < lines.length && lines[i].trim() !== "") i++;
        outLines.push("    restart: unless-stopped");
        break;
      }
      outLines.push(l);
      i++;
    }
    i--;
    continue;
  }

  if (line.includes("driver: overlay")) {
    outLines.push("    driver: bridge");
    continue;
  }
  if (line.trim() === "attachable: true") continue;

  if (line.trim() === "secrets:" && lines[i + 1]?.includes("postgres_password:")) {
    outLines.push("secrets:");
    outLines.push("  postgres_password:");
    outLines.push("    file: ./secrets/postgres_password");
    outLines.push("  postgrest_db_uri:");
    outLines.push("    file: ./secrets/postgrest_db_uri");
    outLines.push("  jwt_secret:");
    outLines.push("    file: ./secrets/jwt_secret");
    outLines.push("  anon_key:");
    outLines.push("    file: ./secrets/anon_key");
    outLines.push("  service_role_key:");
    outLines.push("    file: ./secrets/service_role_key");
    outLines.push("  session_secret:");
    outLines.push("    file: ./secrets/session_secret");
    outLines.push("  inngest_signing_key:");
    outLines.push("    file: ./secrets/inngest_signing_key");
    outLines.push("  inngest_event_key:");
    outLines.push("    file: ./secrets/inngest_event_key");
    outLines.push("  resend_api_key:");
    outLines.push("    file: ./secrets/resend_api_key");
    outLines.push("  smtp_password:");
    outLines.push("    file: ./secrets/smtp_password");
    outLines.push("  saml_private_key:");
    outLines.push("    file: ./secrets/saml_private_key");
    break;
  }

  outLines.push(line);
}

if (!outLines.some((l) => l.trim().startsWith("migrate:"))) {
  const netIdx = outLines.findIndex((l) => l.trim() === "networks:");
  if (netIdx !== -1) {
    const migrate = [
      "",
      "  migrate:",
      "    profiles: [migrate]",
      "    image: ${CARBON_IMAGE_BOOTSTRAP:-carbon/bootstrap:latest}",
      "    networks: [internal]",
      "    secrets:",
      "      - postgres_password",
      "    environment:",
      "      PGSSLMODE: disable",
      "    working_dir: /repo/packages/database",
      "    entrypoint: [\"/bin/sh\", \"-c\"]",
      "    command:",
      "      - >",
      "        pnpm exec supabase migration up --include-all",
      '        --db-url "postgresql://supabase_admin:$$(cat /run/secrets/postgres_password)@postgres:5432/postgres"',
      "    depends_on:",
      "      postgres:",
      "        condition: service_healthy",
      "",
    ];
    outLines.splice(netIdx, 0, ...migrate);
  }
}

writeFileSync(out, `${outLines.join("\n")}\n`);
console.log("Wrote", out);
