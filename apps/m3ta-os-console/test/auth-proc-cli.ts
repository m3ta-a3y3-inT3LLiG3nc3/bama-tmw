import { consumePermit, createSession, mintPermit, registerUser, revokeToken, sessionFromToken } from "../src/auth/registry.ts";

const [command, arg] = process.argv.slice(2);

if (command === "mint") {
  registerUser("ada", "secret", "Ada");
  const session = createSession("ada", "Ada");
  process.stdout.write(session.token);
} else if (command === "probe") {
  process.stdout.write(sessionFromToken(arg ?? "") ? "200" : "401");
} else if (command === "revoke") {
  process.stdout.write(revokeToken(arg ?? "") ? "revoked" : "noop");
} else if (command === "mint-permit") {
  process.stdout.write(mintPermit("ada", "thread-1", "run"));
} else if (command === "consume-permit") {
  process.stdout.write(consumePermit(arg ?? "", "thread-1", "run") ? "yes" : "no");
} else {
  process.stderr.write(`unknown command ${command ?? ""}\n`);
  process.exit(2);
}
