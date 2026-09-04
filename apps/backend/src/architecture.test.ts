import { describe, expect, it } from "bun:test";

describe("backend dependency boundaries", () => {
  it("keeps domain code independent", async () => {
    const sources = await readSources("domain");
    for (const source of sources) {
      expect(source.text).not.toMatch(/from ["'].*application/);
      expect(source.text).not.toMatch(/from ["'].*infrastructure/);
      expect(source.text).not.toMatch(/from ["'](?:elysia|drizzle-orm)/);
    }
  });

  it("keeps application code independent from infrastructure", async () => {
    const sources = await readSources("application");
    for (const source of sources) {
      expect(source.text).not.toMatch(/from ["'].*infrastructure/);
      expect(source.text).not.toMatch(/from ["'](?:elysia|drizzle-orm)/);
    }
  });

  it("keeps database access out of HTTP routers", async () => {
    const sources = await readSources("infrastructure/http/routes");
    for (const source of sources) {
      expect(source.text).not.toMatch(
        /from ["'][^"']*(?:\/db\/|\/repositories\/)/,
      );
      expect(source.text).not.toContain("drizzle-orm");
    }
  });
});

async function readSources(directory: string) {
  const root = new URL(`./${directory}/`, import.meta.url);
  const glob = new Bun.Glob("**/*.ts");
  const files: Array<{ path: string; text: string }> = [];
  for await (const path of glob.scan({ cwd: root.pathname, onlyFiles: true })) {
    if (path.endsWith(".test.ts")) continue;
    files.push({ path, text: await Bun.file(new URL(path, root)).text() });
  }
  return files;
}
