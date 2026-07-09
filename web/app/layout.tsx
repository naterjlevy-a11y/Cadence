import "./globals.css";
import type { Metadata } from "next";
import { AuthHashBridge } from "./components/AuthHashBridge";

export const metadata: Metadata = {
  title: "Cadence — Hold a key. Talk to anything.",
  description:
    "Push-to-talk dictation for your Mac. Hold a key, say where your words should go — Claude, ChatGPT, Docs, anywhere — release, done.",
  openGraph: {
    title: "Cadence — Hold a key. Talk to anything.",
    description:
      "Push-to-talk dictation for your Mac. Speak naturally, release, and your words land where you said — cleaned up and pasted.",
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
