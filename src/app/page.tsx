import { HomeView } from "@/views/home/HomeView";
import { loadServerPlayerProfile } from "@/models/player/serverPlayerProfile.model";

// Profile content depends on the authenticated user's request cookie.
export const dynamic = "force-dynamic";

export default async function Home() {
  const initialPlayerProfile = await loadServerPlayerProfile();

  return <HomeView initialPlayerProfile={initialPlayerProfile} />;
}
