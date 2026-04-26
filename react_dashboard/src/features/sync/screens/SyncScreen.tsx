import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { syncApi, SyncLogItem } from '../api/syncApi';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import {
  RefreshCw,
  AlertTriangle,
  CheckCircle2,
  XCircle,
  Clock,
  Activity,
  Loader2,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

const PAGE_SIZE = 20;

const STATUS_LABELS: Record<string, { label: string; className: string }> = {
  SUCCESS: { label: 'Succès', className: 'bg-green-50 text-green-700 border-green-200' },
  PARTIAL: { label: 'Partiel', className: 'bg-orange-50 text-orange-700 border-orange-200' },
  FAILED:  { label: 'Échec',  className: 'bg-red-50 text-red-700 border-red-200' },
};

function formatDate(iso: string) {
  return new Date(iso).toLocaleString('fr-FR', {
    day: '2-digit', month: '2-digit', year: 'numeric',
    hour: '2-digit', minute: '2-digit',
  });
}

export default function SyncScreen() {
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState<string>('');

  const { data: stats, isLoading: loadingStats } = useQuery({
    queryKey: ['sync', 'stats'],
    queryFn: syncApi.getStats,
    refetchInterval: 60_000,
  });

  const { data: logs, isLoading: loadingLogs } = useQuery({
    queryKey: ['sync', 'logs', page, statusFilter],
    queryFn: () => syncApi.getLogs({ page, page_size: PAGE_SIZE, status: statusFilter || undefined }),
    refetchInterval: 60_000,
  });

  const handleStatusFilter = (value: string) => {
    setStatusFilter(value);
    setPage(1);
  };

  return (
    <div className="space-y-8 animate-in fade-in duration-500">
      {/* Header */}
      <div>
        <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary">Supervision Sync</h2>
        <p className="text-slate-500 text-sm mt-1">Suivi des synchronisations offline → serveur</p>
      </div>

      {/* Stats */}
      {loadingStats ? (
        <div className="flex justify-center py-8">
          <Loader2 className="w-8 h-8 animate-spin text-slate-300" />
        </div>
      ) : stats && (
        <div className="grid grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard
            icon={<Activity className="w-5 h-5" />}
            label="Synchronisations"
            value={stats.total_syncs}
            sub={stats.last_sync_at ? `Dernière : ${formatDate(stats.last_sync_at)}` : 'Aucune sync'}
            color="blue"
          />
          <StatCard
            icon={<RefreshCw className="w-5 h-5" />}
            label="Enregistrements sync."
            value={stats.total_records_synced}
            color="green"
          />
          <StatCard
            icon={<AlertTriangle className="w-5 h-5" />}
            label="Conflits détectés"
            value={stats.total_conflicts}
            color={stats.total_conflicts > 0 ? 'orange' : 'green'}
            highlight={stats.total_conflicts > 0}
          />
          <div className="bg-white rounded-2xl border border-slate-200 p-5 shadow-sm space-y-3">
            <p className="text-xs text-slate-400 uppercase font-bold tracking-wider">Statuts</p>
            <div className="space-y-1.5">
              <StatusRow icon={<CheckCircle2 className="w-3.5 h-3.5 text-green-500" />} label="Succès"  count={stats.success_count} />
              <StatusRow icon={<Clock       className="w-3.5 h-3.5 text-orange-400" />} label="Partiel" count={stats.partial_count} />
              <StatusRow icon={<XCircle     className="w-3.5 h-3.5 text-red-500"    />} label="Échec"   count={stats.failed_count} />
            </div>
          </div>
        </div>
      )}

      {/* Logs */}
      <Card className="border-slate-200 shadow-sm bg-white overflow-hidden">
        <CardHeader className="flex flex-row items-center justify-between border-b border-slate-100 bg-slate-50/30 py-4">
          <div className="space-y-0.5">
            <CardTitle className="text-lg text-schooltrack-primary">Journaux de synchronisation</CardTitle>
            <CardDescription className="text-xs">
              {logs ? `${logs.total} sync${logs.total > 1 ? 's' : ''} au total` : ''}
            </CardDescription>
          </div>
          {/* Filtre statut */}
          <div className="flex items-center gap-2">
            {(['', 'SUCCESS', 'PARTIAL', 'FAILED'] as const).map((s) => (
              <button
                key={s}
                onClick={() => handleStatusFilter(s)}
                className={cn(
                  'px-3 py-1.5 rounded-lg text-xs font-semibold border transition-all',
                  statusFilter === s
                    ? 'bg-schooltrack-primary text-white border-schooltrack-primary'
                    : 'bg-white text-slate-500 border-slate-200 hover:border-schooltrack-primary hover:text-schooltrack-primary'
                )}
              >
                {s === '' ? 'Tous' : STATUS_LABELS[s].label}
              </button>
            ))}
          </div>
        </CardHeader>

        <CardContent className="p-0">
          {loadingLogs ? (
            <div className="flex justify-center py-12">
              <Loader2 className="w-6 h-6 animate-spin text-slate-300" />
            </div>
          ) : !logs?.items.length ? (
            <div className="py-12 text-center text-slate-400 text-sm">Aucune synchronisation enregistrée.</div>
          ) : (
            <>
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-slate-100 bg-slate-50/50 text-xs text-slate-400 uppercase tracking-wider">
                      <th className="text-left px-4 py-3 font-semibold">Date</th>
                      <th className="text-left px-4 py-3 font-semibold">Voyage</th>
                      <th className="text-left px-4 py-3 font-semibold">Enseignant</th>
                      <th className="text-left px-4 py-3 font-semibold">Statut</th>
                      <th className="text-right px-4 py-3 font-semibold">Enreg.</th>
                      <th className="text-right px-4 py-3 font-semibold">Conflits</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-50">
                    {logs.items.map((log) => (
                      <LogRow key={log.id} log={log} />
                    ))}
                  </tbody>
                </table>
              </div>

              {/* Pagination */}
              {logs.total_pages > 1 && (
                <div className="flex items-center justify-between px-4 py-3 border-t border-slate-100">
                  <span className="text-xs text-slate-400">
                    Page {logs.page} / {logs.total_pages}
                  </span>
                  <div className="flex gap-2">
                    <Button
                      variant="outline" size="sm"
                      disabled={page === 1}
                      onClick={() => setPage(p => p - 1)}
                      className="h-8 w-8 p-0"
                    >
                      <ChevronLeft className="w-4 h-4" />
                    </Button>
                    <Button
                      variant="outline" size="sm"
                      disabled={page === logs.total_pages}
                      onClick={() => setPage(p => p + 1)}
                      className="h-8 w-8 p-0"
                    >
                      <ChevronRight className="w-4 h-4" />
                    </Button>
                  </div>
                </div>
              )}
            </>
          )}
        </CardContent>
      </Card>
    </div>
  );
}

// ---- Composants internes ----

function StatCard({
  icon, label, value, sub, color, highlight,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  sub?: string;
  color: 'blue' | 'green' | 'orange';
  highlight?: boolean;
}) {
  const colorMap = {
    blue:   { bg: 'bg-blue-50',   text: 'text-schooltrack-action',   val: 'text-schooltrack-primary' },
    green:  { bg: 'bg-green-50',  text: 'text-schooltrack-success',  val: 'text-schooltrack-primary' },
    orange: { bg: 'bg-orange-50', text: 'text-orange-500',           val: 'text-orange-600' },
  };
  const c = colorMap[color];
  return (
    <div className={cn(
      'bg-white rounded-2xl border p-5 shadow-sm space-y-3',
      highlight ? 'border-orange-300' : 'border-slate-200'
    )}>
      <div className={cn('w-9 h-9 rounded-xl flex items-center justify-center', c.bg, c.text)}>
        {icon}
      </div>
      <div>
        <p className="text-xs text-slate-400 uppercase font-bold tracking-wider">{label}</p>
        <p className={cn('text-3xl font-black', c.val)}>{value.toLocaleString()}</p>
        {sub && <p className="text-[10px] text-slate-400 mt-0.5">{sub}</p>}
      </div>
    </div>
  );
}

function StatusRow({ icon, label, count }: { icon: React.ReactNode; label: string; count: number }) {
  return (
    <div className="flex items-center justify-between">
      <span className="flex items-center gap-1.5 text-xs text-slate-500">{icon}{label}</span>
      <span className="text-xs font-bold text-slate-700">{count}</span>
    </div>
  );
}

function LogRow({ log }: { log: SyncLogItem }) {
  const s = STATUS_LABELS[log.status] ?? { label: log.status, className: '' };
  return (
    <tr className="hover:bg-slate-50/50 transition-colors">
      <td className="px-4 py-3 text-slate-500 whitespace-nowrap text-xs">
        {formatDate(log.synced_at)}
      </td>
      <td className="px-4 py-3 font-medium text-slate-800 max-w-[160px] truncate">
        {log.trip_name ?? <span className="text-slate-400 italic">—</span>}
      </td>
      <td className="px-4 py-3 text-slate-500 text-xs max-w-[160px] truncate">
        {log.user_email ?? <span className="italic">—</span>}
      </td>
      <td className="px-4 py-3">
        <Badge variant="outline" className={cn('text-[10px] font-bold', s.className)}>
          {s.label}
        </Badge>
      </td>
      <td className="px-4 py-3 text-right text-slate-700 font-semibold">{log.records_synced}</td>
      <td className="px-4 py-3 text-right">
        {log.conflicts_detected > 0 ? (
          <span className="inline-flex items-center gap-1 text-orange-600 font-bold text-xs">
            <AlertTriangle className="w-3 h-3" />
            {log.conflicts_detected}
          </span>
        ) : (
          <span className="text-slate-300 text-xs">0</span>
        )}
      </td>
    </tr>
  );
}
