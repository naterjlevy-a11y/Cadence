import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./app/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        mello: {
          DEFAULT: "#7c9cff",
          deep: "#5c7ce0",
          glow: "#b7c6ff",
          ink: "#0b0d12",
          surface: "#141821",
          paper: "#f7f9ff",
          peri: "#8fa8ff",
          coral: "#ffb454",
          sky: "#dbe4ff",
          cream: "#f7f9ff",
        },
      },
      fontFamily: {
        sans: ["Inter", "ui-sans-serif", "system-ui", "-apple-system", "Segoe UI", "Helvetica Neue", "sans-serif"],
        display: ["'Instrument Serif'", "ui-serif", "Georgia", "serif"],
        mono: ["'IBM Plex Mono'", "ui-monospace", "SFMono-Regular", "Menlo", "monospace"],
      },
      letterSpacing: {
        tightest: "-0.04em",
      },
    },
  },
  plugins: [],
};
export default config;
