import { useParams, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { tripApi, type CheckpointTimelineEntry } from '../api/tripApi';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  Loader2, ArrowLeft, Flag, Users, ScanLine, Timer, CheckCircle2, Circle,
} from 'lucide-react';

export default function CheckpointTimelineScreen() {
  const { id: tripId } = useParams<{ id: string }>();
  const navigate = useNavigate();

  const { data: summary, isLoading, error } = useQuery({
    queryKey: ['checkpoints-summary', tripId],
    queryFn: () => tripApi.getCheckpointsSummary(tripId!),
    enabled: !!tripId,
    refetchOnWindowFocus: false,
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <Loader2 className="h-8 w-8 animate-spin text-schooltrack-primary" />
      </div>
    );
  }

  if (error || !summary) {
    return (
      <div className="text-center py-16 text-red-500">
        Impossible de charger les checkpoints.
      </div>
    );
  }

  return (
    <div className="p-6 space-y-6 max-w-[1000px] mx-auto">
      {/* Header */}
      <div className="flex items-center gap-4">
        <Button variant="ghost" size="icon" onClick={() => navigate(-1)}>
          <ArrowLeft className="h-5 w-5" />
        </Button>
        <div>
          <h1 className="text-lg font-semibold">Timeline — {summary.trip_destination}</h1>
          <p className="text-sm text-slate-500">Checkpoints du voyage</p>
        </div>
      </div>

      {/* Stats cards */}
      <div className="grid grid-cols-2 lg:grid-cols-5 gap-3">
        <StatCard label="Total" value={summary.total_checkpoints} icon={Flag} color="text-indigo-600" bg="bg-indigo-50" />
        <StatCard label="Actifs" value={summary.active_checkpoints} icon={Circle} color="text-blue-600" bg="bg-blue-50" />
        <StatCard label="Fermes" value={summary.closed_checkpoints} icon={CheckCircle2} color="text-green-600" bg="bg-green-50" />
        <StatCard label="Total scans" value={summary.total_scans} icon={ScanLine} color="text-purple-600" bg="bg-purple-50" />
        <StatCard
          label="Duree moy."
          value={summary.avg_duration_minutes != null ? `${summary.avg_duration_minutes.toFixed(0)} min` : '-'}
          icon={Timer}
          color="text-orange-600"
          bg="bg-orange-50"
        />
      </div>

      {/* Timeline */}
      {!summary.timeline?.length ? (
        <p className="text-center text-slate-400 py-12">Aucun checkpoint enregistre.</p>
      ) : (
        <div className="relative ml-6">
          {/* Vertical line */}
          <div className="absolute left-3 top-0 bottom-0 w-0.5 bg-slate-200" />

          <div className="space-y-4">
            {summary.timeline.map((cp) => (
              <TimelineEntry key={cp.id} checkpoint={cp} />
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Stat Card ──────────────────────────────────────────────────────────

function StatCard({ label, value, icon: Icon, color, bg }: {
  label: string;
  value: string | number;
  icon: React.ElementType;
  color: string;
  bg: string;
}) {
  return (
    <Card className="border-slate-200">
      <CardContent className="flex items-center gap-3 p-4">
        <div className={`p-2 rounded-lg ${bg}`}>
          <Icon className={`h-4 w-4 ${color}`} />
        </div>
        <div>
          <p className="text-[10px] text-slate-400 uppercase">{label}</p>
          <p className={`text-lg font-bold ${color}`}>{value}</p>
        </div>
      </CardContent>
    </Card>
  );
}

// ─── Timeline Entry ─────────────────────────────────────────────────────

function TimelineEntry({ checkpoint: cp }: { checkpoint: CheckpointTimelineEntry }) {
  const isClosed = cp.status === 'CLOSED';
  const dotColor = isClosed ? 'bg-green-500' : 'bg-blue-500';

  return (
    <div className="relative pl-10">
      {/* Dot */}
      <div className={`absolute left-1.5 top-5 w-3 h-3 rounded-full border-2 border-white ${dotColor} shadow`} />

      <Card className="border-slate-200">
        <CardContent className="p-4">
          <div className="flex items-start justify-between">
            <div>
              <div className="flex items-center gap-2 mb-1">
                <h3 className="font-semibold text-sm">{cp.name}</h3>
                <span className={`px-2 py-0.5 rounded-full text-[10px] font-semibold ${isClosed ? 'bg-green-100 text-green-700' : 'bg-blue-100 text-blue-700'}`}>
                  {isClosed ? 'Ferme' : 'Actif'}
                </span>
              </div>

              <div className="flex items-center gap-4 text-xs text-slate-500 flex-wrap">
                <span className="flex items-center gap-1">
                  <ScanLine className="h-3 w-3" /> {cp.scan_count} scans
                </span>
                <span className="flex items-center gap-1">
                  <Users className="h-3 w-3" /> {cp.student_count} eleves
                </span>
                {cp.duration_minutes != null && (
                  <span className="flex items-center gap-1">
                    <Timer className="h-3 w-3" /> {cp.duration_minutes.toFixed(0)} min
                  </span>
                )}
                {cp.created_by_name && (
                  <span className="text-slate-400">par {cp.created_by_name}</span>
                )}
              </div>

              {cp.created_at && (
                <p className="text-[10px] text-slate-400 mt-1">
                  {new Date(cp.created_at).toLocaleString('fr-BE', { day: '2-digit', month: '2-digit', year: 'numeric', hour: '2-digit', minute: '2-digit' })}
                </p>
              )}
            </div>

            <div className="flex items-center gap-2">
              <span className="text-xs text-slate-400">{cp.scan_count} scan{cp.scan_count !== 1 ? 's' : ''}</span>
            </div>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
