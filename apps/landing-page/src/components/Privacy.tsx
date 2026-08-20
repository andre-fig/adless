import { UserX, KeyRound, Eye, DollarSign } from "lucide-react";
import { useLanguage } from "@/i18n/LanguageContext";

const Privacy = () => {
  const { t } = useLanguage();

  const privacyPoints = [
    { icon: UserX, text: t('noLogin') },
    { icon: KeyRound, text: t('noAccount') },
    { icon: Eye, text: t('noTracking') },
    { icon: DollarSign, text: t('noDataSelling') },
  ];

  return (
    <section className="py-24 px-6">
      <div className="container max-w-4xl mx-auto text-center">
        <h2 className="text-display-sm md:text-display-md text-foreground mb-6">
          {t('privacyTitle1')}<br />
          <span className="text-accent">{t('privacyTitle2')}</span>
        </h2>

        <p className="text-body-lg text-muted-foreground max-w-xl mx-auto mb-12">
          {t('privacySubtitle')}
        </p>

        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          {privacyPoints.map((point, index) => (
            <div
              key={index}
              className="bg-card rounded-2xl p-6 shadow-card"
            >
              <div className="w-12 h-12 bg-accent/10 rounded-xl flex items-center justify-center mx-auto mb-4">
                <point.icon className="w-6 h-6 text-accent" />
              </div>
              <p className="text-body-md font-medium text-foreground">
                {point.text}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default Privacy;
