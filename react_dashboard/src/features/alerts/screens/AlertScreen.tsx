import { useState, useEffect, useCallback } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getAlerts, getAlertStats, updateAlertStatus, type AlertData, type AlertStats } from '../api/alertApi';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  RefreshCw, Loader2, AlertTriangle, Bell, Clock, CheckCircle2,
  ShieldAlert, AlertCircle, Info, ChevronRight, MapPin, Users, Flag,
} from 'lucide-react';

const STATUS_OPTIONS = [
  { value: 'ACTIVE', label: 'Actives' },
  { value: 'IN_PROGRESS', label: 'En cours' },
  { value: 'RESOLVED', label: 'Resolues' },
  { value: 'ALL', label: 'Toutes' },
];

const POLLING_MS = 30_000;

export default function AlertScreen() {
  const [statusFilter, setStatusFilter] = useState('ACTIVE');
  const queryClient = useQueryClient();

  const { data: alerts, isLoading: loadingAlerts, refetch: refetchAlerts } = useQuery({
    queryKey: ['alerts', statusFilter],
    queryFn: () => getAlerts({ status: statusFilter === 'ALL' ? undefined : statusFilter }),
    refetchOnWindowFocus: false,
    retry: 1,
  });

  const { data: stats, refetch: refetchStats } = useQuery({
    queryKey: ['alert-stats'],
    queryFn: () => getAlertStats(),
    refetchOnWindowFocus: false,
    retry: 1,
  });

  // Polling 30s
  useEffect(() => {
    const interval = setInterval(() => {
      queryClient.invalidateQueries({ queryKey: ['alerts'] });
      queryClient.invalidateQueries({ queryKey: ['alert-stats'] });
    }, POLLING_MS);
    return () => clearInterval(interval);
  }, [queryClient]);

  const mutation = useMutation({
    mutationFn: ({ alertId, status }: { alertId: string; status: string }) =>
      updateAlertStatus(alertId, status),
    onSuccess: () => {
      refetchAlerts();
      refetchStats();
    },
  });

  const handleRefresh = useCallback(() => {
    refetchAlerts();
    refetchStats();
  }, [refetchAlerts, refetchStats]);

  if (loadingAlerts && !alerts) {
    return (
      <div className="flex items-center justify-center h-96">
        <Loader2 className="h-8 w-8 animate-spin text-schooltrack-primary" />
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6 max-w-[1200px] mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between">
        <p className="text-slate-500">Alertes temps reel</p>
        <div className="flex items-center gap-3">
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="w-40">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {STATUS_OPTIONS.map(o => (
                <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button variant="outline" size="icon" onClick={handleRefresh}>
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* Stats */}
      {stats && <StatsRow stats={stats} />}

      {/* Liste alertes */}
      {!alerts || alerts.length === 0 ? (
        <div className="text-center py-16 text-slate-400">
          <Bell className="h-12 w-12 mx-auto mb-4 opacity-40" />
          <p>Aucune alerte {statusFilter !== 'ALL' ? `avec le statut "${STATUS_OPTIONS.find(o => o.value === statusFilter)?.label}"` : ''}</p>
        </div>
      ) : (
        <div className="space-y-3">
          {alerts.map(alert => (
            <AlertCard
              key={alert.id}
              alert={alert}
              onUpdateStatus={(status) => mutation.mutate({ alertId: alert.id, status })}
              isUpdating={mutation.isPending}
            />
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Stats Row ──────────────────────────────────────────────────────────

function StatsRow({ stats }: { stats: AlertStats }) {
  const items = [
    { label: 'Actives', value: stats.active, icon: AlertCircle, color: 'text-red-600', bg: 'bg-red-50' },
    { label: 'En cours', value: stats.in_progress, icon: Clock, color: 'text-orange-600', bg: 'bg-orange-50' },
    { label: 'Resolues', value: stats.resolved, icon: CheckCircle2, color: 'text-green-600', bg: 'bg-green-50' },
    { label: 'Critiques', value: stats.critical_count, icon: ShieldAlert, color: 'text-red-700', bg: 'bg-red-100' },
  ];

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
      {items.map(s => (
        <Card key={s.label} className="border-slate-200">
          <CardContent className="flex items-center gap-3 p-4">
            <div className={`p-2 rounded-lg ${s.bg}`}>
              <s.icon className={`h-5 w-5 ${s.color}`} />
            </div>
            <div>
              <p className="text-xs text-slate-500">{s.label}</p>
              <p className={`text-xl font-bold ${s.color}`}>{s.value}</p>
            </div>
          </CardContent>
        </Card>
      ))}
    </div>
  );
}

// ─── Alert Card ─────────────────────────────────────────────────────────

function severityInfo(severity: string) {
  switch (severity) {
    case 'CRITICAL': return { label: 'Critique', className: 'bg-red-100 text-red-700', icon: ShieldAlert };
    case 'HIGH': return { label: 'Haute', className: 'bg-orange-100 text-orange-700', icon: AlertTriangle };
    case 'MEDIUM': return { label: 'Moyenne', className: 'bg-yellow-100 text-yellow-700', icon: AlertCircle };
    case 'LOW': return { label: 'Faible', className: 'bg-blue-100 text-blue-700', icon: Info };
    default: return { label: severity, className: 'bg-slate-100 text-slate-600', icon: Info };
  }
}

function statusBadge(status: string) {
  switch (status) {
    case 'ACTIVE': return { label: 'Active', className: 'bg-red-100 text-red-700' };
    case 'IN_PROGRESS': return { label: 'En cours', className: 'bg-orange-100 text-orange-700' };
    case 'RESOLVED': return { label: 'Resolue', className: 'bg-green-100 text-green-700' };
    default: return { label: status, className: 'bg-slate-100 text-slate-600' };
  }
}

function alertTypeLabel(type: string) {
  switch (type) {
    case 'STUDENT_MISSING': return 'Eleve manquant';
    case 'CHECKPOINT_DELAYED': return 'Checkpoint en retard';
    case 'SYNC_FAILED': return 'Echec synchronisation';
    default: return type;
  }
}

function formatTime(iso: string) {
  const d = new Date(iso);
  return d.toLocaleString('fr-BE', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

interface AlertCardProps {
  alert: AlertData;
  onUpdateStatus: (status: string) => void;
  isUpdating: boolean;
}

function AlertCard({ alert, onUpdateStatus, isUpdating }: AlertCardProps) {
  const sev = severityInfo(alert.severity);
  const st = statusBadge(alert.status);
  const SevIcon = sev.icon;

  return (
    <Card className="border-slate-200">
      <CardContent className="p-5">
        <div className="flex items-start gap-4">
          {/* Severity icon */}
          <div className={`p-2 rounded-lg ${sev.className.split(' ')[0]}`}>
            <SevIcon className={`h-5 w-5 ${sev.className.split(' ')[1]}`} />
          </div>

          {/* Content */}
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-2 flex-wrap mb-1">
              <span className={`px-2 py-0.5 rounded-full text-[11px] font-semibold ${sev.className}`}>{sev.label}</span>
              <span className={`px-2 py-0.5 rounded-full text-[11px] font-semibold ${st.className}`}>{st.label}</span>
              <span className="text-xs text-slate-400">{alertTypeLabel(alert.alert_type)}</span>
            </div>

            {alert.message && (
              <p className="text-sm text-slate-700 mb-2">{alert.message}</p>
            )}

            <div className="flex items-center gap-4 text-xs text-slate-500 flex-wrap">
              {alert.student_name && (
                <span className="flex items-center gap-1"><Users className="h-3 w-3" /> {alert.student_name}</span>
              )}
              <span className="flex items-center gap-1"><MapPin className="h-3 w-3" /> {alert.trip_destination}</span>
              {alert.checkpoint_name && (
                <span className="flex items-center gap-1"><Flag className="h-3 w-3" /> {alert.checkpoint_name}</span>
              )}
              <span className="flex items-center gap-1"><Clock className="h-3 w-3" /> {formatTime(alert.created_at)}</span>
            </div>
          </div>

          {/* Actions */}
          <div className="flex flex-col gap-2 flex-shrink-0">
            {alert.status === 'ACTIVE' && (
              <Button
                size="sm"
                variant="outline"
                onClick={() => onUpdateStatus('IN_PROGRESS')}
                disabled={isUpdating}
                className="text-xs"
              >
                Prendre en charge <ChevronRight className="ml-1 h-3 w-3" />
              </Button>
            )}
            {(alert.status === 'ACTIVE' || alert.status === 'IN_PROGRESS') && (
              <Button
                size="sm"
                onClick={() => onUpdateStatus('RESOLVED')}
                disabled={isUpdating}
                className="text-xs bg-green-600 hover:bg-green-700"
              >
                Resoudre <CheckCircle2 className="ml-1 h-3 w-3" />
              </Button>
            )}
          </div>
        </div>
      </CardContent>
    </Card>
  );
}
