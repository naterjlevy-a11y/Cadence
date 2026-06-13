import "./globals.css";
import type { Metadata } from "next";
import { AuthHashBridge } from "./components/AuthHashBridge";

export const metadata: Metadata = {
  title: "Mellotron — Voice routing for your Mac",
  description:
    "Hold a key, talk to any app. Mellotron transcribes with Groq Whisper, cleans your text with AI, and pastes it where it belongs.",
  openGraph: {
    title: "Mellotron",
    description: "Push-to-talk dictation for macOS, powered by Groq Whisper.",
    type: "website",
  },
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className="bg-mello-ink text-mello-paper">
      <body className="font-sans antialiased min-h-dvh selection:bg-mello/30 selection:text-white">
        <AuthHashBridge />
        {children}
      </body>
    </html>
  );
}
