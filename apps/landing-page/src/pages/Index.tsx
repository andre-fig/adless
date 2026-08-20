import { Helmet } from "react-helmet-async";
import { useLanguage } from "@/i18n/LanguageContext";
import Hero from "@/components/Hero";
import Benefits from "@/components/Benefits";
import HowItWorks from "@/components/HowItWorks";
import Comparison from "@/components/Comparison";
import Privacy from "@/components/Privacy";
import CTA from "@/components/CTA";
import Footer from "@/components/Footer";
import ThemeToggle from "@/components/ThemeToggle";
import LanguageSelector from "@/components/LanguageSelector";

const Index = () => {
  const { t } = useLanguage();
  return (
    <>
      <Helmet>
        <title>{t("pageTitle")}</title>
        <meta name="description" content={t("pageDescription")} />
        <meta property="og:title" content={t("pageTitle")} />
        <meta property="og:description" content={t("pageDescription")} />
        <meta name="twitter:card" content="summary_large_image" />
        <link rel="canonical" href="https://andre-fig.github.io/adless/" />
      </Helmet>

      <LanguageSelector />
      <ThemeToggle />
      <main>
        <Hero />
        <Benefits />
        <HowItWorks />
        <Comparison />
        <Privacy />
        <CTA />
      </main>
      <Footer />
    </>
  );
};

export default Index;
