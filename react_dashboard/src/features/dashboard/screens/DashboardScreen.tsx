import { useState, useEffect, useCallback } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getDashboardOverview, type DashboardOverview, type DashboardTripSummary, type ScanMethodStats } from '../api/dashboardApi';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';
import {
  PieChart, Pie, Cell, Tooltip as RechartsTooltip, ResponsiveContainer,
  BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip as BarTooltip,
} from 'recharts';
import {
  RefreshCw, Bus, Clock, Users, CheckCircle, Loader2, AlertTriangle,
  MapPin, Flag,
} from 'lucide-react';

const STATUS_OPTIONS = [
  { value: 'ALL', label: 'Tous les statuts' },
  { value: 'ACTIVE', label: 'En cours' },
  { value: 'PLANNED', label: 'A venir' },
  { value: 'COMPLETED', label: 'Termines' },
];

const AUTO_REFRESH_MS = 60_000;

export default function DashboardScreen() {
  const [statusFilter, setStatusFilter] = useState('ALL');
  const queryClient = useQueryClient();

  const { data: overview, isLoading, error, refetch } = useQuery({
    queryKey: ['dashboard-overview', statusFilter],
    queryFn: () => getDashboardOverview(statusFilter),
    refetchOnWindowFocus: false,
    retry: 1,
  });

  // Auto-refresh toutes les 60 secondes
  useEffect(() => {
    const interval = setInterval(() => {
      queryClient.invalidateQueries({ queryKey: ['dashboard-overview', statusFilter] });
    }, AUTO_REFRESH_MS);
    return () => clearInterval(interval);
  }, [statusFilter, queryClient]);

  const handleFilterChange = useCallback((value: string) => {
    setStatusFilter(value);
  }, []);

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-96">
        <Loader2 className="h-8 w-8 animate-spin text-schooltrack-primary" />
      </div>
    );
  }

  if (error && !overview) {
    return (
      <div className="flex flex-col items-center justify-center h-96 gap-4">
        <AlertTriangle className="h-12 w-12 text-red-400" />
        <p className="text-red-600">{(error as Error).message}</p>
        <Button onClick={() => refetch()} variant="outline">
          <RefreshCw className="mr-2 h-4 w-4" /> Reessayer
        </Button>
      </div>
    );
  }

  if (!overview) return null;

  return (
    <div className="p-6 space-y-6 max-w-[1400px] mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between">
        <p className="text-slate-500">Statistiques et suivi en temps reel</p>
        <div className="flex items-center gap-3">
          <Select value={statusFilter} onValueChange={handleFilterChange}>
            <SelectTrigger className="w-48">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {STATUS_OPTIONS.map(o => (
                <SelectItem key={o.value} value={o.value}>{o.label}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Button variant="outline" size="icon" onClick={() => refetch()}>
            <RefreshCw className="h-4 w-4" />
          </Button>
        </div>
      </div>

      {/* 4 cartes stats globales */}
      <GlobalStatsRow overview={overview} />

      {/* Graphique modes de scan + Resume */}
      <div className="grid grid-cols-1 lg:grid-cols-5 gap-4">
        <div className="lg:col-span-2">
          <ScanMethodChart stats={overview.scan_method_stats} />
        </div>
        <div className="lg:col-span-3">
          <GlobalAttendanceCard overview={overview} />
        </div>
      </div>

      {/* Liste des voyages */}
      <div>
        <h2 className="text-lg font-semibold mb-3">Voyages ({overview.total_trips})</h2>
        {overview.trips.length === 0 ? (
          <p className="text-center text-slate-500 py-8">Aucun voyage pour le filtre selectionne.</p>
        ) : (
          <div className="space-y-4">
            {overview.trips.map(trip => (
              <TripOverviewCard key={trip.id} trip={trip} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── 4 cartes stats globales ────────────────────────────────────────────

function GlobalStatsRow({ overview }: { overview: DashboardOverview }) {
  const rateColor = overview.global_attendance_rate >= 80
    ? 'text-green-600' : overview.global_attendance_rate >= 50
    ? 'text-orange-500' : 'text-red-600';

  const stats = [
    { label: 'Voyages actifs', value: overview.active_trips, icon: Bus, color: 'text-green-600', bg: 'bg-green-50' },
    { label: 'A venir', value: overview.planned_trips, icon: Clock, color: 'text-blue-600', bg: 'bg-blue-50' },
    { label: 'Total eleves', value: overview.total_students, icon: Users, color: 'text-indigo-600', bg: 'bg-indigo-50' },
    { label: 'Taux presence global', value: `${overview.global_attendance_rate.toFixed(1)}%`, icon: CheckCircle, color: rateColor, bg: overview.global_attendance_rate >= 80 ? 'bg-green-50' : overview.global_attendance_rate >= 50 ? 'bg-orange-50' : 'bg-red-50' },
  ];

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3">
      {stats.map(s => (
        <Card key={s.label} className="border-slate-200">
          <CardContent className="flex items-center gap-4 p-4">
            <div className={`p-2.5 rounded-lg ${s.bg}`}>
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

// ─── Camembert modes de scan ────────────────────────────────────────────

const SCAN_COLORS = ['#2563eb', '#ea580c', '#9333ea', '#6b7280'];

function ScanMethodChart({ stats }: { stats: ScanMethodStats }) {
  const hasData = stats.total > 0;

  const data = [
    { name: 'NFC', value: stats.nfc, color: SCAN_COLORS[0] },
    { name: 'QR Physique', value: stats.qr_physical, color: SCAN_COLORS[1] },
    { name: 'QR Digital', value: stats.qr_digital, color: SCAN_COLORS[2] },
    { name: 'Manuel', value: stats.manual, color: SCAN_COLORS[3] },
  ].filter(d => d.value > 0);

  return (
    <Card className="border-slate-200 h-full">
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Modes de scan</CardTitle>
      </CardHeader>
      <CardContent>
        {!hasData ? (
          <p className="text-center text-slate-400 py-10">Aucun scan enregistre</p>
        ) : (
          <div className="flex items-center gap-4">
            <ResponsiveContainer width="50%" height={160}>
              <PieChart>
                <Pie
                  data={data}
                  dataKey="value"
                  cx="50%"
                  cy="50%"
                  innerRadius={30}
                  outerRadius={60}
                  paddingAngle={2}
                  label={({ percent }: { percent?: number }) => percent != null ? `${(percent * 100).toFixed(0)}%` : ''}
                  labelLine={false}
                  style={{ fontSize: 11, fontWeight: 600, fill: '#fff' }}
                >
                  {data.map((d, i) => (
                    <Cell key={i} fill={d.color} />
                  ))}
                </Pie>
                <RechartsTooltip formatter={(value, name) => [`${value} scans`, name]} />
              </PieChart>
            </ResponsiveContainer>
            <div className="space-y-2">
              {[
                { label: 'NFC', count: stats.nfc, color: SCAN_COLORS[0] },
                { label: 'QR Physique', count: stats.qr_physical, color: SCAN_COLORS[1] },
                { label: 'QR Digital', count: stats.qr_digital, color: SCAN_COLORS[2] },
                { label: 'Manuel', count: stats.manual, color: SCAN_COLORS[3] },
              ].map(l => (
                <div key={l.label} className="flex items-center gap-2 text-xs">
                  <span className="w-2.5 h-2.5 rounded-full" style={{ backgroundColor: l.color }} />
                  <span>{l.label} ({l.count})</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

// ─── Carte resume global ────────────────────────────────────────────────

function GlobalAttendanceCard({ overview }: { overview: DashboardOverview }) {
  const rate = overview.global_attendance_rate;
  const barColor = rate >= 80 ? 'bg-green-500' : rate >= 50 ? 'bg-orange-500' : 'bg-red-500';

  return (
    <Card className="border-slate-200 h-full">
      <CardHeader className="pb-2">
        <CardTitle className="text-base">Resume</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2">
        <SummaryRow label="Total voyages" value={overview.total_trips.toString()} />
        <SummaryRow label="Voyages termines" value={overview.completed_trips.toString()} />
        <SummaryRow label="Total scans" value={overview.total_attendances.toString()} />
        <SummaryRow label="Taux presence global" value={`${rate.toFixed(1)}%`} />
        <div className="mt-3 h-2 bg-slate-200 rounded-full overflow-hidden">
          <div className={`h-full ${barColor} rounded-full transition-all`} style={{ width: `${Math.min(rate, 100)}%` }} />
        </div>
      </CardContent>
    </Card>
  );
}

function SummaryRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-slate-500">{label}</span>
      <span className="font-semibold">{value}</span>
    </div>
  );
}

// ─── Carte voyage avec bar chart checkpoints ────────────────────────────

const MONTHS = ['jan', 'fev', 'mar', 'avr', 'mai', 'juin', 'juil', 'aout', 'sep', 'oct', 'nov', 'dec'];

function formatDate(dateStr: string) {
  const d = new Date(dateStr);
  return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

function statusInfo(status: string): { label: string; className: string } {
  switch (status) {
    case 'ACTIVE': return { label: 'En cours', className: 'bg-green-100 text-green-700' };
    case 'PLANNED': return { label: 'A venir', className: 'bg-blue-100 text-blue-700' };
    case 'COMPLETED': return { label: 'Termine', className: 'bg-slate-100 text-slate-600' };
    default: return { label: status, className: 'bg-slate-100 text-slate-500' };
  }
}

function TripOverviewCard({ trip }: { trip: DashboardTripSummary }) {
  const si = statusInfo(trip.status);
  const rate = trip.attendance_rate;
  const rateColor = rate >= 80 ? 'text-green-600' : rate >= 50 ? 'text-orange-500' : 'text-red-600';
  const ringColor = rate >= 80 ? '#16a34a' : rate >= 50 ? '#f97316' : '#dc2626';

  const chartData = trip.checkpoints.map(cp => ({
    name: cp.name.length > 10 ? cp.name.slice(0, 10) + '...' : cp.name,
    fullName: cp.name,
    rate: cp.attendance_rate,
    present: cp.total_present,
    expected: cp.total_expected,
  }));

  return (
    <Card className="border-slate-200">
      <CardContent className="p-5">
        {/* Header */}
        <div className="flex items-start justify-between">
          <div>
            <h3 className="font-semibold text-base">{trip.destination}</h3>
            <div className="flex items-center gap-3 mt-1 text-xs text-slate-500 flex-wrap">
              <span className={`px-2 py-0.5 rounded-full text-[11px] font-semibold ${si.className}`}>{si.label}</span>
              <span>{formatDate(trip.date)}</span>
              <span className="flex items-center gap-1"><Users className="h-3 w-3" /> {trip.total_present}/{trip.total_students}</span>
              <span className="flex items-center gap-1"><Flag className="h-3 w-3" /> {trip.closed_checkpoints}/{trip.total_checkpoints} checkpoints</span>
            </div>
          </div>
          {/* Taux circulaire */}
          <div className="relative w-14 h-14 flex-shrink-0">
            <svg className="w-full h-full -rotate-90" viewBox="0 0 36 36">
              <circle cx="18" cy="18" r="15" fill="none" stroke="#e2e8f0" strokeWidth="3" />
              <circle cx="18" cy="18" r="15" fill="none" stroke={ringColor} strokeWidth="3"
                strokeDasharray={`${rate * 0.942} 100`} strokeLinecap="round" />
            </svg>
            <span className={`absolute inset-0 flex items-center justify-center text-xs font-bold ${rateColor}`}>
              {rate.toFixed(0)}%
            </span>
          </div>
        </div>

        {/* Bar chart checkpoints */}
        {chartData.length > 0 && (
          <div className="mt-4">
            <ResponsiveContainer width="100%" height={160}>
              <BarChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="#e2e8f0" />
                <XAxis dataKey="name" tick={{ fontSize: 10, fill: '#64748b' }} />
                <YAxis domain={[0, 100]} tick={{ fontSize: 10, fill: '#64748b' }} tickFormatter={v => `${v}%`} />
                <BarTooltip
                  content={({ active, payload }) => {
                    if (!active || !payload?.length) return null;
                    const d = payload[0].payload;
                    return (
                      <div className="bg-slate-800 text-white text-xs px-3 py-2 rounded shadow">
                        <p className="font-semibold">{d.fullName}</p>
                        <p>{d.present}/{d.expected} ({d.rate.toFixed(0)}%)</p>
                      </div>
                    );
                  }}
                />
                <Bar dataKey="rate" radius={[4, 4, 0, 0]} maxBarSize={24}>
                  {chartData.map((d, i) => (
                    <Cell key={i} fill={d.rate >= 80 ? '#22c55e' : d.rate >= 50 ? '#f97316' : '#ef4444'} />
                  ))}
                </Bar>
              </BarChart>
            </ResponsiveContainer>
          </div>
        )}

        {/* Dernier checkpoint */}
        {trip.last_checkpoint && (
          <div className="mt-3 flex items-center gap-1 text-xs text-slate-500">
            <MapPin className="h-3 w-3" />
            <span>Dernier checkpoint : {trip.last_checkpoint.name} ({trip.last_checkpoint.attendance_rate.toFixed(0)}%)</span>
          </div>
        )}
      </CardContent>
    </Card>
  );
}
