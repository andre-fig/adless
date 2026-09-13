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
import Seo from "@/components/Seo";
import { languageHomePath } from "@/lib/site";

const Index = () => {
  const { language, t } = useLanguage();

  return (
    <>
      <Seo
        title={t("pageTitle")}
        description={t("pageDescription")}
        path={languageHomePath(language)}
        language={language}
        localizedPath="/"
        structuredData
      />

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
