"use client";

import Link from "next/link";
import { destinationHref, formatPhase8Time } from "@/lib/phase8/format";
import type { Notification } from "@/services/types";

const content = (notification: Notification) => (
  <>
    <span
      className={`mt-1.5 h-2 w-2 shrink-0 rounded-full ${notification.readAt ? "bg-border" : "bg-bordeaux"}`}
    />
    <span className="min-w-0 flex-1">
      <span className="block text-sm">{notification.body}</span>
      <span className="mt-1 block text-xs text-muted-foreground">
        {formatPhase8Time(notification.createdAt)} · {notification.category}
      </span>
    </span>
    {!notification.readAt && (
      <span className="rounded-full bg-bordeaux/10 px-2 py-0.5 text-[10px] font-medium text-bordeaux">
        Nuova
      </span>
    )}
  </>
);

export const NotificationItem = ({
  notification,
  onRead,
}: {
  notification: Notification;
  onRead: (id: string) => void;
}) => {
  const href = destinationHref(notification.destination);
  const className = `flex w-full items-start gap-3 rounded-2xl border border-border p-4 text-left transition hover:shadow-sm ${notification.readAt ? "bg-card" : "bg-crema"}`;

  return href ? (
    <Link href={href} onClick={() => onRead(notification.id)} className={className}>
      {content(notification)}
    </Link>
  ) : (
    <button onClick={() => onRead(notification.id)} className={className}>
      {content(notification)}
    </button>
  );
};
