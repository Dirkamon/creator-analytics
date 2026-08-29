export type MagicLinkState = {
  status: "idle" | "success" | "error";
  message: string;
};

export const initialMagicLinkState: MagicLinkState = {
  status: "idle",
  message: "",
};
