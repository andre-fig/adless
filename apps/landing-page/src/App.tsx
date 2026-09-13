import { useState } from "react";
import type { ComponentProps, ReactNode } from "react";
import { Toaster } from "@/components/ui/toaster";
import { Toaster as Sonner } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Route, Routes, useLocation } from "react-router-dom";
import { HelmetProvider } from "react-helmet-async";
import { ThemeProvider } from "@/components/ThemeProvider";
import { LanguageProvider } from "@/i18n/LanguageContext";
import type { Language } from "@/i18n/translations";
import { languageFromPath } from "@/lib/site";
import Index from "./pages/Index";
import NotFound from "./pages/NotFound";
import PrivacyPolicy from "./pages/PrivacyPolicy";
import Support from "./pages/Support";
import Terms from "./pages/Terms";

type HelmetContext = ComponentProps<typeof HelmetProvider>["context"];

type AppProvidersProps = {
  children: ReactNode;
  initialLanguage?: Language;
  helmetContext?: HelmetContext;
};

export const AppProviders = ({
  children,
  initialLanguage,
  helmetContext,
}: AppProvidersProps) => {
  const [queryClient] = useState(() => new QueryClient());

  return (
    <ThemeProvider
      attribute="class"
      defaultTheme="system"
      enableSystem
      disableTransitionOnChange={false}
    >
      <LanguageProvider initialLanguage={initialLanguage}>
        <HelmetProvider context={helmetContext}>
          <QueryClientProvider client={queryClient}>
            <TooltipProvider>
              <Toaster />
              <Sonner />
              {children}
            </TooltipProvider>
          </QueryClientProvider>
        </HelmetProvider>
      </LanguageProvider>
    </ThemeProvider>
  );
};

export const AppRoutes = () => (
  <Routes>
    <Route path="/" element={<Index />} />
    <Route path="/en" element={<Index />} />
    <Route path="/pt-br" element={<Index />} />
    <Route path="/es" element={<Index />} />
    <Route path="/en/privacy" element={<PrivacyPolicy />} />
    <Route path="/en/terms" element={<Terms />} />
    <Route path="/en/support" element={<Support />} />
    <Route path="/pt-br/privacy" element={<PrivacyPolicy />} />
    <Route path="/pt-br/terms" element={<Terms />} />
    <Route path="/pt-br/support" element={<Support />} />
    <Route path="/es/privacy" element={<PrivacyPolicy />} />
    <Route path="/es/terms" element={<Terms />} />
    <Route path="/es/support" element={<Support />} />
    <Route path="/privacy" element={<PrivacyPolicy />} />
    <Route path="/terms" element={<Terms />} />
    <Route path="/support" element={<Support />} />
    <Route path="*" element={<NotFound />} />
  </Routes>
);

const RoutedApp = () => {
  const { pathname } = useLocation();
  const initialLanguage = languageFromPath(pathname) ?? "en";

  return (
    <AppProviders initialLanguage={initialLanguage}>
      <AppRoutes />
    </AppProviders>
  );
};

const App = () => (
  <BrowserRouter basename={import.meta.env.BASE_URL}>
    <RoutedApp />
  </BrowserRouter>
);

export default App;
