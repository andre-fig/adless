import { renderToString } from "react-dom/server";
import { StaticRouter } from "react-router-dom/server";
import type { HelmetServerState } from "react-helmet-async";
import { AppProviders, AppRoutes } from "./App";
import type { Language } from "./i18n/translations";

type RenderResult = {
  appHtml: string;
  headHtml: string;
  htmlAttributes: string;
};

export const renderPage = (url: string, language: Language): RenderResult => {
  const helmetContext: { helmet?: HelmetServerState } = {};
  const appHtml = renderToString(
    <AppProviders initialLanguage={language} helmetContext={helmetContext}>
      <StaticRouter location={url}>
        <AppRoutes />
      </StaticRouter>
    </AppProviders>,
  );
  const helmet = helmetContext.helmet;

  if (!helmet) {
    throw new Error(`SEO metadata was not generated for ${url}`);
  }

  return {
    appHtml,
    htmlAttributes: helmet.htmlAttributes.toString(),
    headHtml: [
      helmet.title.toString(),
      helmet.meta.toString(),
      helmet.link.toString(),
      helmet.script.toString(),
    ]
      .join("\n    ")
      .split("hrefLang=")
      .join("hreflang="),
  };
};
