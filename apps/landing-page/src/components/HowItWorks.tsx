import { ArrowRight } from "lucide-react";
import { useLanguage } from "@/i18n/LanguageContext";

const HowItWorks = () => {
  const { t } = useLanguage();

  const steps = [
    {
      number: "01",
      title: t("step1Title"),
      description: t("step1Desc"),
    },
    {
      number: "02",
      title: t("step2Title"),
      description: t("step2Desc"),
    },
    {
      number: "03",
      title: t("step3Title"),
      description: t("step3Desc"),
    },
    {
      number: "04",
      title: t("step4Title"),
      description: t("step4Desc"),
    },
  ];

  return (
    <section className="py-24 px-6">
      <div className="container max-w-4xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-display-sm md:text-display-md text-foreground mb-4">
            {t("howTitle")}
          </h2>
          <p className="text-body-lg text-muted-foreground max-w-xl mx-auto">
            {t("howSubtitle")}
          </p>
        </div>

        <div className="space-y-4">
          {steps.map((step, index) => (
            <div
              key={step.number}
              className="flex items-start gap-6 bg-card rounded-2xl p-6 shadow-card"
            >
              <div className="flex-shrink-0 w-12 h-12 bg-accent/10 rounded-xl flex items-center justify-center">
                <span className="text-accent font-semibold text-body-md">
                  {step.number}
                </span>
              </div>
              <div className="flex-grow">
                <h3 className="text-heading-md text-foreground mb-1">
                  {step.title}
                </h3>
                <p className="text-body-md text-muted-foreground">
                  {step.description}
                </p>
              </div>
              {index < steps.length - 1 && (
                <ArrowRight className="w-5 h-5 text-muted-foreground/40 hidden md:block flex-shrink-0 mt-1" />
              )}
            </div>
          ))}
        </div>

        {/* Important note */}
        <div className="mt-8 p-5 bg-secondary/70 rounded-xl border border-border">
          <p className="text-body-sm text-muted-foreground text-center">
            <span className="font-medium text-foreground">
              {t("noteLabel")}
            </span>{" "}
            {t("howNote")}
          </p>
        </div>
      </div>
    </section>
  );
};

export default HowItWorks;
