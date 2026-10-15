import type { ReactNode } from "react";
import { cn } from "@/lib/utils";

/** Pure CSS landscape phone: a thin dark body around a 16:9 screen (same ratio as the screenshots, nothing is cropped). */
export function PhoneFrame({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn("relative rounded-[20px] bg-[#2b2f3a] p-[3px]", className)}>
      <div className="relative aspect-[16/9] overflow-hidden rounded-[17px] bg-black">
        {children}
      </div>
      <span
        aria-hidden
        className="absolute left-[7px] top-1/2 size-[4px] -translate-y-1/2 rounded-full bg-[#0b0d14]"
      />
    </div>
  );
}
