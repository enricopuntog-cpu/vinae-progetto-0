"use client";

import Link from "next/link";
import { Bell, MessageCircle } from "lucide-react";
import { Popover, PopoverContent, PopoverTrigger } from "@/components/ui/popover";
import { formatPhase8Time } from "@/lib/phase8/format";
import { usePhase8 } from "@/lib/phase8/phase8-context";

export const HeaderInboxActions = () => {
  const {
    notifications,
    unreadCount,
    messageUnreadCount,
    markNotificationRead,
    markAllNotificationsRead,
  } = usePhase8();

  return (
    <>
      <Link
        href="/messaggi"
        aria-label="Messaggi"
        data-testid="header-messages-link"
        className="relative rounded-full p-2 hover:bg-secondary"
      >
        <MessageCircle className="h-5 w-5" />
        {messageUnreadCount > 0 && (
          <span className="absolute right-1 top-1 grid h-4 min-w-4 place-items-center rounded-full bg-bordeaux px-1 text-[10px] font-semibold text-crema">
            {messageUnreadCount}
          </span>
        )}
      </Link>
      <Popover>
        <PopoverTrigger asChild>
          <button
            aria-label="Notifiche"
            data-testid="header-notifications-btn"
            className="relative rounded-full p-2 hover:bg-secondary"
          >
            <Bell className="h-5 w-5" />
            {unreadCount > 0 && (
              <span className="absolute right-1 top-1 grid h-4 min-w-4 place-items-center rounded-full bg-bordeaux px-1 text-[10px] font-semibold text-crema">
                {unreadCount}
              </span>
            )}
          </button>
        </PopoverTrigger>
        <PopoverContent align="end" className="w-80 p-0">
          <div className="flex items-center justify-between border-b px-4 py-3">
            <p className="font-serif text-lg font-semibold">Notifiche</p>
            <button
              onClick={() => void markAllNotificationsRead()}
              disabled={unreadCount === 0}
              className="text-xs text-bordeaux hover:underline disabled:opacity-40"
            >
              Segna lette
            </button>
          </div>
          <ul className="max-h-80 overflow-y-auto">
            {notifications.slice(0, 6).map((notification) => (
              <li key={notification.id}>
                <button
                  onClick={() => void markNotificationRead(notification.id)}
                  className={`flex w-full gap-2 border-b px-4 py-3 text-left last:border-0 hover:bg-secondary/50 ${notification.readAt ? "" : "bg-crema"}`}
                >
                  {!notification.readAt && (
                    <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-bordeaux" />
                  )}
                  <span className="min-w-0 flex-1">
                    <span className="block text-sm">{notification.body}</span>
                    <span className="mt-1 block text-xs text-muted-foreground">
                      {formatPhase8Time(notification.createdAt)} · {notification.category}
                    </span>
                  </span>
                </button>
              </li>
            ))}
          </ul>
          <div className="border-t p-2">
            <Link
              href="/notifiche"
              className="block rounded-md px-3 py-2 text-center text-sm font-medium text-bordeaux hover:bg-secondary"
            >
              Vedi tutte le notifiche →
            </Link>
          </div>
        </PopoverContent>
      </Popover>
    </>
  );
};
