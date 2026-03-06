import { getDefaultConfig } from "@rainbow-me/rainbowkit";
import { avalancheFuji } from "wagmi/chains";

export const config = getDefaultConfig({
  appName: "Meridian Protocol",
  projectId: process.env.NEXT_PUBLIC_WALLETCONNECT_PROJECT_ID || "meridian-dev",
  chains: [avalancheFuji],
  ssr: true,
});
