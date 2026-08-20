import { Moon, Sun } from "lucide-react";
import { useTheme } from "next-themes";
import { useEffect, useState } from "react";

const ThemeToggle = () => {
  const { theme, setTheme, resolvedTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    setMounted(true);
  }, []);

  if (!mounted) {
    return (
      <button
        className="fixed top-5 right-5 z-50 w-10 h-10 rounded-full bg-card shadow-apple-md flex items-center justify-center border border-border/50 transition-all duration-300"
        aria-label="Toggle theme"
      >
        <div className="w-5 h-5 bg-muted rounded-full animate-pulse" />
      </button>
    );
  }

  const toggleTheme = () => {
    // Add transitioning class for smooth animation
    document.documentElement.classList.add('transitioning');

    if (resolvedTheme === 'dark') {
      setTheme('light');
    } else {
      setTheme('dark');
    }

    // Remove transitioning class after animation
    setTimeout(() => {
      document.documentElement.classList.remove('transitioning');
    }, 350);
  };

  return (
    <button
      onClick={toggleTheme}
      className="fixed top-5 right-5 z-50 w-10 h-10 rounded-full bg-card shadow-apple-md flex items-center justify-center border border-border/50 transition-all duration-300 hover:shadow-apple-lg hover:scale-105 active:scale-95"
      aria-label={`Switch to ${resolvedTheme === 'dark' ? 'light' : 'dark'} mode`}
    >
      {resolvedTheme === 'dark' ? (
        <Sun className="w-5 h-5 text-foreground transition-transform duration-300" />
      ) : (
        <Moon className="w-5 h-5 text-foreground transition-transform duration-300" />
      )}
    </button>
  );
};

export default ThemeToggle;
