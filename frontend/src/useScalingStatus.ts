import { useEffect, useState } from "react";
import { getScalingStatus } from "./api";
import type { ScalingStatus } from "./types";

export interface ScalingViewProps {
  scaling: ScalingStatus | null;
  scalingError: boolean;
}

export function useScalingStatus(): ScalingViewProps {
  const [scaling, setScaling] = useState<ScalingStatus | null>(null);
  const [scalingError, setScalingError] = useState(false);
  useEffect(() => {
    let disposed = false;
    let timer: ReturnType<typeof setTimeout>;
    const refresh = async () => {
      try {
        const status = await getScalingStatus();
        if (!disposed) { setScaling(status); setScalingError(false); }
      } catch {
        if (!disposed) { setScaling(null); setScalingError(true); }
      } finally {
        if (!disposed) timer = setTimeout(refresh, 3000);
      }
    };
    void refresh();
    return () => { disposed = true; clearTimeout(timer); };
  }, []);
  return { scaling, scalingError };
}
