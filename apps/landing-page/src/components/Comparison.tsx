import { Check, X } from "lucide-react";
import { useLanguage } from "@/i18n/LanguageContext";

const ComparisonItem = ({
  label,
  adless,
  others
}: {
  label: string;
  adless: boolean;
  others: boolean;
}) => (
  <div className="grid grid-cols-3 gap-4 py-4 border-b border-border last:border-0">
    <div className="text-body-md text-foreground">{label}</div>
    <div className="flex justify-center">
      {adless ? (
        <div className="w-6 h-6 bg-success/15 rounded-full flex items-center justify-center">
          <Check className="w-4 h-4 text-success" />
        </div>
      ) : (
        <div className="w-6 h-6 bg-destructive/15 rounded-full flex items-center justify-center">
          <X className="w-4 h-4 text-destructive" />
        </div>
      )}
    </div>
    <div className="flex justify-center">
      {others ? (
        <div className="w-6 h-6 bg-success/15 rounded-full flex items-center justify-center">
          <Check className="w-4 h-4 text-success" />
        </div>
      ) : (
        <div className="w-6 h-6 bg-destructive/15 rounded-full flex items-center justify-center">
          <X className="w-4 h-4 text-destructive" />
        </div>
      )}
    </div>
  </div>
);

const Comparison = () => {
  const { t } = useLanguage();

  return (
    <section className="py-24 px-6 bg-secondary/50">
      <div className="container max-w-3xl mx-auto">
        <div className="text-center mb-16">
          <h2 className="text-display-sm md:text-display-md text-foreground mb-4">
            {t('comparisonTitle')}
          </h2>
          <p className="text-body-lg text-muted-foreground max-w-xl mx-auto">
            {t('comparisonSubtitle')}
          </p>
        </div>

        <div className="bg-card rounded-2xl p-6 md:p-8 shadow-card">
          {/* Header */}
          <div className="grid grid-cols-3 gap-4 pb-4 border-b border-border mb-2">
            <div className="text-body-sm font-medium text-muted-foreground">{t('feature')}</div>
            <div className="text-body-sm font-semibold text-accent text-center">Adless</div>
            <div className="text-body-sm font-medium text-muted-foreground text-center">{t('others')}</div>
          </div>

          {/* Comparison rows */}
          <ComparisonItem label={t('localBlocking')} adless={true} others={false} />
          <ComparisonItem label={t('noExternalServers')} adless={true} others={false} />
          <ComparisonItem label={t('noDataCollection')} adless={true} others={false} />
          <ComparisonItem label={t('nativeInterface')} adless={true} others={false} />
          <ComparisonItem label={t('oneTimePurchase')} adless={true} others={false} />
        </div>
      </div>
    </section>
  );
};

export default Comparison;
