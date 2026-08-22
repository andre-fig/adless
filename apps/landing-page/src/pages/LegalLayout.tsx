import type { ReactNode } from "react";

type LegalLayoutProps = {
  title: string;
  updatedAt: string;
  children: ReactNode;
};

const LegalLayout = ({ title, updatedAt, children }: LegalLayoutProps) => (
  <main className="min-h-screen px-6 py-16 md:py-24">
    <article className="container max-w-3xl mx-auto rounded-3xl bg-card p-8 shadow-card md:p-12">
      <a
        href={import.meta.env.BASE_URL}
        className="text-sm font-medium text-accent hover:underline"
      >
        Adless
      </a>
      <h1 className="mt-8 text-display-sm text-foreground md:text-display-md">{title}</h1>
      <p className="mt-3 text-sm text-muted-foreground">Last updated: {updatedAt}</p>
      <div className="prose prose-slate mt-10 max-w-none dark:prose-invert">{children}</div>
    </article>
  </main>
);

export default LegalLayout;
