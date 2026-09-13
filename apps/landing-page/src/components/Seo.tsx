import { Helmet } from "react-helmet-async";
import type { Language } from "@/i18n/translations";
import {
  APP_STORE_URL,
  SITE_ORIGIN,
  SOCIAL_IMAGE_PATH,
  languageConfig,
} from "@/lib/site";

type SeoProps = {
  title: string;
  description: string;
  path: string;
  language?: Language;
  localizedPath?: string;
  noIndex?: boolean;
  structuredData?: boolean;
};

const Seo = ({
  title,
  description,
  path,
  language = "en",
  localizedPath,
  noIndex = false,
  structuredData = false,
}: SeoProps) => {
  const locale = languageConfig[language];
  const canonicalURL = `${SITE_ORIGIN}${path}`;
  const socialImageURL = `${SITE_ORIGIN}${SOCIAL_IMAGE_PATH}`;
  const appSchema = {
    "@context": "https://schema.org",
    "@type": "SoftwareApplication",
    name: "Adless",
    description,
    url: canonicalURL,
    downloadUrl: APP_STORE_URL,
    operatingSystem: "iOS, iPadOS",
    applicationCategory: "UtilitiesApplication",
    inLanguage: locale.htmlLang,
    image: socialImageURL,
    publisher: {
      "@type": "Organization",
      name: "Orbe Works",
      url: "https://orbe.works/",
    },
  };

  return (
    <Helmet htmlAttributes={{ lang: locale.htmlLang }}>
      <title>{title}</title>
      <meta name="description" content={description} />
      <meta name="author" content="Adless" />
      {noIndex && <meta name="robots" content="noindex, nofollow" />}

      <link rel="canonical" href={canonicalURL} />
      {localizedPath &&
        (Object.entries(languageConfig) as Array<
          [Language, (typeof languageConfig)[Language]]
        >).map(([alternateLanguage, config]) => (
          <link
            key={alternateLanguage}
            rel="alternate"
            hrefLang={config.htmlLang}
            href={`${SITE_ORIGIN}${
              localizedPath === "/"
                ? config.path
                : `${config.path.slice(0, -1)}${localizedPath}`
            }`}
          />
        ))}
      {localizedPath && (
        <link
          rel="alternate"
          hrefLang="x-default"
          href={`${SITE_ORIGIN}${
            localizedPath === "/" ? "/en/" : `/en${localizedPath}`
          }`}
        />
      )}

      <meta property="og:site_name" content="Adless" />
      <meta property="og:type" content="website" />
      <meta property="og:title" content={title} />
      <meta property="og:description" content={description} />
      <meta property="og:url" content={canonicalURL} />
      <meta property="og:image" content={socialImageURL} />
      <meta property="og:image:alt" content="Adless app icon" />
      <meta property="og:locale" content={locale.ogLocale} />
      {localizedPath &&
        Object.values(languageConfig)
          .filter((config) => config.ogLocale !== locale.ogLocale)
          .map((config) => (
            <meta
              key={config.ogLocale}
              property="og:locale:alternate"
              content={config.ogLocale}
            />
          ))}

      <meta name="twitter:card" content="summary_large_image" />
      <meta name="twitter:title" content={title} />
      <meta name="twitter:description" content={description} />
      <meta name="twitter:image" content={socialImageURL} />
      <meta name="twitter:image:alt" content="Adless app icon" />

      {structuredData && (
        <script type="application/ld+json">{JSON.stringify(appSchema)}</script>
      )}
    </Helmet>
  );
};

export default Seo;
