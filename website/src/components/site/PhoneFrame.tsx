import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/** Pure CSS landscape phone: dark body, camera dot on the left, side button, glare. Screen ratio 19.5:9. */
export function PhoneFrame({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div
      className={cn(
        "relative rounded-[36px] bg-[#0e1230] p-[10px] shadow-[0_28px_50px_-18px_rgba(14,18,48,0.65),0_0_0_2px_#2a3263]",
        className,
      )}
    >
      <div className="relative aspect-[19.5/9] overflow-hidden rounded-[26px] bg-black">
        {children}
        <div
          aria-hidden
          className="pointer-events-none absolute inset-0 bg-gradient-to-br from-white/20 via-transparent to-transparent"
        />
      </div>
      <span
        aria-hidden
        className="absolute left-[3px] top-1/2 size-[7px] -translate-y-1/2 rounded-full bg-[#050714] ring-1 ring-[#2a3263]"
      />
      <span
        aria-hidden
        className="absolute -right-[3px] top-[26%] h-[16%] w-[3px] rounded-r bg-[#2a3263]"
      />
    </div>
  );
}
