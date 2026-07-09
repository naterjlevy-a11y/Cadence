import { AliasMarquee } from "./components/landing/AliasMarquee";
import { Destinations } from "./components/landing/Destinations";
import { Engine } from "./components/landing/Engine";
import { FAQ } from "./components/landing/FAQ";
import { Footer } from "./components/landing/Footer";
import { HeroDemo } from "./components/landing/HeroDemo";
import { MarqueeBand } from "./components/landing/MarqueeBand";
import { Nav } from "./components/landing/Nav";
import { PillPortal } from "./components/landing/PillPortal";
import { Preloader } from "./components/landing/Preloader";
import { Pricing } from "./components/landing/Pricing";
import { Privacy } from "./components/landing/Privacy";
import { SmoothScroll } from "./components/landing/SmoothScroll";
import { ThreeMovements } from "./components/landing/ThreeMovements";
import { Why } from "./components/landing/Why";

export default function Home() {
  return (
    <main className="relative isolate min-h-dvh overflow-x-clip bg-mello-ink text-white">
      {/* Subtle grain only — no gradients or halos. Pure purple-on-black. */}
      <div className="pointer-events-none absolute inset-0 -z-10 grain opacity-50" />

      <Preloader />
      <SmoothScroll />

      <Nav />
      <PillPortal />
      <HeroDemo />
      <MarqueeBand text="push to talk · hold · speak · release" />
      <AliasMarquee />
      <ThreeMovements />
      <Destinations />
      <Why />
      <Engine />
      <Privacy />
      <Pricing />
      <FAQ />
      <Footer />
    </main>
  );
}
