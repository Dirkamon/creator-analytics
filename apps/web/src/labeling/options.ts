// Matches the existing Google Sheets `Lists` tab verified for the Phase 3
// coexistence workflow. Database migration 035 enforces the same vocabulary.
export const labelGames = [
  "Rainbow Six Siege",
  "RLCraft",
  "Minecraft",
  "Subnautica 2",
  "ARK Survival Evolved",
  "Black Ops 3 Zombies",
  "Ready or Not",
  "Arc Raiders",
  "Escape the Backrooms",
  "Terraria",
  "Skyrim",
  "Marvel Rivals",
  "REPO",
  "Other",
  "Battlefield",
  "Halo campaign evolved",
] as const;

export const labelContentTypes = [
  "Squad banter",
  "Fail",
  "Clutch",
  "Out-of-context",
  "Funny moment",
  "Reaction",
  "Story",
  "Gameplay highlight",
  "Gaming news",
  "Tutorial",
  "Compilation",
  "Other",
] as const;

export const labelVibes = [
  "Funny",
  "Chaotic",
  "Casual",
  "Intense",
  "Dry/deadpan",
  "Wholesome",
  "Frustrated",
  "Informative",
] as const;

export const labelHookTypes = [
  "Immediate dialogue",
  "Immediate action",
  "Text setup",
  "Question",
  "Reaction first",
  "Slow setup",
  "No explicit hook",
  "Other",
] as const;

export const labelEditingIntensities = ["Light", "Medium", "Heavy"] as const;
