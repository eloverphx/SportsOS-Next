import { BroadcastOverlayClient } from "../../../../components/broadcast/BroadcastOverlayClient";

export default async function BroadcastOverlayPage({
  params,
}: {
  params: Promise<{
    gameId: string;
  }>;
}) {
  const { gameId } = await params;

  return (
    <BroadcastOverlayClient gameId={gameId} />
  );
}
