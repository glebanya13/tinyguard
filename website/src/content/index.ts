import type { Locale } from "@/config/site";
import { en } from "./en";
import { ru } from "./ru";
import type { Content } from "./types";

export function getContent(locale: Locale): Content {
  return locale === "en" ? en : ru;
}
