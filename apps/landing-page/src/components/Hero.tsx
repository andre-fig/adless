import adlessLogo from "@/assets/adless-logo.png";
import { useLanguage } from "@/i18n/LanguageContext";

const Hero = () => {
  const { t } = useLanguage();

  return (
    <section className="relative min-h-screen flex items-center justify-center px-6 py-24">
      <div className="container max-w-4xl mx-auto text-center">
        {/* Logo */}
        <div className="mb-10 animate-scale-in" style={{ animationFillMode: 'both' }}>
          <img
            src={adlessLogo}
            alt="Adless"
            className="w-28 h-28 md:w-36 md:h-36 mx-auto rounded-[1.75rem] shadow-apple-lg"
          />
        </div>

        {/* Headline */}
        <h1 className="text-display-md md:text-display-lg lg:text-display-xl text-foreground mb-6 animate-fade-in-up" style={{ animationDelay: '0.1s', animationFillMode: 'both' }}>
          {t('heroHeadline1')}<br />
          <span className="text-accent">{t('heroHeadline2')}</span>
        </h1>

        {/* Subheadline */}
        <p className="text-body-lg md:text-heading-md text-muted-foreground max-w-2xl mx-auto mb-10 animate-fade-in-up font-normal" style={{ animationDelay: '0.2s', animationFillMode: 'both' }}>
          {t('heroSubheadline')}
        </p>

        {/* App Store Button */}
        <div className="animate-fade-in-up" style={{ animationDelay: '0.3s', animationFillMode: 'both' }}>
          <a
            href="#"
            className="inline-flex items-center gap-3 bg-foreground hover:bg-foreground/90 text-background px-7 py-4 rounded-xl transition-all duration-300 hover:scale-[1.02] active:scale-[0.98] shadow-apple-md"
            aria-label="Download on the App Store"
          >
            <svg
              className="w-7 h-7"
              viewBox="0 0 24 24"
              fill="currentColor"
            >
              <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
            </svg>
            <div className="text-left">
              <div className="text-[10px] font-medium opacity-80 leading-none">{t('downloadOnThe')}</div>
              <div className="text-lg font-semibold leading-tight -mt-0.5">{t('appStore')}</div>
            </div>
          </a>
        </div>

        {/* Availability note */}
        <p className="mt-6 text-body-sm text-muted-foreground animate-fade-in" style={{ animationDelay: '0.4s', animationFillMode: 'both' }}>
          {t('availableFor')}
        </p>
      </div>
    </section>
  );
};

export default Hero;
