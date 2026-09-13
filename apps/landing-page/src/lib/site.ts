import type { Language } from "@/i18n/translations";

export const SITE_ORIGIN = "https://adless.orbe.works";
export const APP_STORE_URL = "https://apps.apple.com/app/id6803552143";
export const SOCIAL_IMAGE_PATH = "/adless-social.png?v=2";

export const languageConfig: Record<
  Language,
  { path: string; htmlLang: string; ogLocale: string }
> = {
  en: { path: "/en/", htmlLang: "en", ogLocale: "en_US" },
  pt: { path: "/pt-br/", htmlLang: "pt-BR", ogLocale: "pt_BR" },
  es: { path: "/es/", htmlLang: "es", ogLocale: "es_ES" },
};

export const languageFromPath = (pathname: string): Language | undefined => {
  if (pathname === "/pt-br" || pathname.startsWith("/pt-br/")) return "pt";
  if (pathname === "/es" || pathname.startsWith("/es/")) return "es";
  if (pathname === "/en" || pathname.startsWith("/en/")) return "en";
  return undefined;
};

export const languageHomePath = (language: Language) => languageConfig[language].path;

export const localizedPathForLanguage = (language: Language, pathname: string) => {
  const pathWithoutLocale = pathname.replace(/^\/(?:en|pt-br|es)(?=\/|$)/, "") || "/";
  const localizedRoot = languageHomePath(language).slice(0, -1);
  return pathWithoutLocale === "/" ? `${localizedRoot}/` : `${localizedRoot}${pathWithoutLocale}`;
};
