"use client";

import Nav from "@/components/Nav";
import Hero from "@/sections/Hero";
import Stats from "@/sections/Stats";
import Problem from "@/sections/Problem";
import Solution from "@/sections/Solution";
import HowItWorks from "@/sections/HowItWorks";
import Traction from "@/sections/Traction";
import Team from "@/sections/Team";
import Footer from "@/sections/Footer";

export default function Home() {
  return (
    <>
      <Nav />
      <main>
        <Hero />
        <Stats />
        <Problem />
        <Solution />
        <HowItWorks />
        <Traction />
        <Team />
        <Footer />
      </main>
    </>
  );
}
