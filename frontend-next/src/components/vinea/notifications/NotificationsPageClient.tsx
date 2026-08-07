"use client";

import { useMemo, useState } from "react";
import { Button } from "@/components/ui/button";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { EmptyState, ErrorState, LoadingBlock, OfflineState, useOnline } from "@/components/vinea/States";
import { NotificationItem } from "@/components/vinea/notifications/NotificationItem";
import { RealtimeStatusBanner } from "@/components/vinea/notifications/RealtimeStatusBanner";
import { usePhase8 } from "@/lib/phase8/phase8-context";
import type { Notification } from "@/services/types";

const tabs = [
  { value: "tutte", label: "Tutte" },
  { value: "marketplace", label: "Marketplace" },
  { value: "community", label: "Club" },
  { value: "sistema", label: "Sistema" },
] as const;

type Tab = (typeof tabs)[number]["value"];

export const NotificationsPageClient = () => {
  const {
    notifications,
    unreadCount,
    loading,
    error,
    reload,
    markNotificationRead,
    markAllNotificationsRead,
    realtimeState,
  } = usePhase8();
  const online = useOnline();
  const [tab, setTab] = useState<Tab>("tutte");
  const visible = useMemo(
    () =>
      tab === "tutte"
        ? notifications
        : notifications.filter((notification) => notification.category === tab),
    [notifications, tab],
  );

  if (!online && notifications.length === 0) return <OfflineState onRetry={() => void reload()} />;
  if (loading && notifications.length === 0) return <LoadingBlock label="Caricamento notifiche" />;
  if (error && notifications.length === 0) {
    return <ErrorState message={error} onRetry={() => void reload()} />;
  }

  const markRead = (id: string) => void markNotificationRead(id);
  return (
    <div className="space-y-6">
      <header className="flex items-end justify-between gap-4">
        <div>
          <h1 className="font-serif text-3xl md:text-4xl">Notifiche</h1>
          <p className="text-muted-foreground">{unreadCount} non lette</p>
        </div>
        <Button
          variant="outline"
          disabled={unreadCount === 0 || !online}
          onClick={() => void markAllNotificationsRead()}
        >
          Segna tutte come lette
        </Button>
      </header>
      <RealtimeStatusBanner state={realtimeState} />
      <Tabs value={tab} onValueChange={(value) => setTab(value as Tab)}>
        <TabsList className="bg-secondary">
          {tabs.map((item) => (
            <TabsTrigger key={item.value} value={item.value}>
              {item.label}
            </TabsTrigger>
          ))}
        </TabsList>
        <TabsContent value={tab} className="mt-4 space-y-2">
          {visible.length === 0 ? (
            <EmptyState
              title="Nessuna notifica"
              message="Non ci sono notifiche in questa categoria."
            />
          ) : (
            visible.map((notification: Notification) => (
              <NotificationItem
                key={notification.id}
                notification={notification}
                onRead={markRead}
              />
            ))
          )}
        </TabsContent>
      </Tabs>
    </div>
  );
};
