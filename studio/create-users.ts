import { ApiKey, User } from "../../models/objection";

const userAddress = "0x601CFcDA730f6EDfD4B6aF95e9A698fF56bC21F0";
const userPrivateKey =
  "1ac4bf849afb47228e4deaa1a6faa710ffe816690ca7892fdcd23b8a4329bdc3";

export async function seed(): Promise<void> {
  const user = await User.findOrCreate({ ethAddress: userAddress });
  console.log("Created user", { user });
  const apiKey = await ApiKey.findOrCreate({
    name: "testKey",
    displayName: "testKey",
    userId: user.id,
    isSubsidized: true,
  });
  console.log("Created API key", { apiKey });
}
