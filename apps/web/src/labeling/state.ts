export type LabelingActionState = {
  status: "idle" | "success" | "error";
  message: string;
};

export const initialLabelingActionState: LabelingActionState = {
  status: "idle",
  message: "",
};
