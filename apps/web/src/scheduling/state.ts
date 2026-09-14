export type ScheduleDecisionActionState = {
  status: "idle" | "success" | "error";
  message: string;
};

export const initialScheduleDecisionActionState: ScheduleDecisionActionState = {
  status: "idle",
  message: "",
};
