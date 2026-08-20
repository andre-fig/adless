import { Shield, Lock, Zap, Cpu, Apple } from "lucide-react";
import { useLanguage } from "@/i18n/LanguageContext";

const Benefits = () => {
  const { t } = useLanguage();

  const benefits = [
    {
      icon: Shield,
      title: t('benefit1Title'),
      description: t('benefit1Desc'),
    },
    {
      icon: Lock,
      title: t('benefit2Title'),
      description: t('benefit2Desc'),
    },
    {
      icon: Zap,
      title: t('benefit3Title'),
      description: t('benefit3Desc'),
    },
    {
      icon: Cpu,
      title: t('benefit4Title'),
      description: t('benefit4Desc'),
    },
    {
      icon: Apple,
      title: t('benefit5Title'),
      description: t('benefit5Desc'),
    },
  ];

  return (
    <section className="py-24 px-6 bg-secondary/50">
      <div className="container max-w-5xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-display-sm md:text-display-md text-foreground mb-4">
            {t('benefitsTitle')}
          </h2>
          <p className="text-body-lg text-muted-foreground max-w-xl mx-auto">
            {t('benefitsSubtitle')}
          </p>
        </div>

        <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-4">
          {benefits.map((benefit, index) => (
            <div
              key={index}
              className="group bg-card rounded-2xl p-6 shadow-card hover:shadow-apple-md transition-all duration-300"
            >
              <div className="w-12 h-12 bg-accent/10 rounded-xl flex items-center justify-center mb-4 group-hover:bg-accent/15 transition-colors">
                <benefit.icon className="w-6 h-6 text-accent" />
              </div>
              <h3 className="text-heading-md text-foreground mb-2">
                {benefit.title}
              </h3>
              <p className="text-body-md text-muted-foreground">
                {benefit.description}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
};

export default Benefits;
