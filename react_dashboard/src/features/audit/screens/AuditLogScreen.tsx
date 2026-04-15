import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { auditApi } from '../api/auditApi';
import type { AuditLog } from '../api/auditApi';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import {
  Calendar, User, Shield, ChevronLeft, ChevronRight,
  Loader2, Globe, Download, FilterX, X,
} from 'lucide-react';

// ----------------------------------------------------------------
// Traduction des actions backend → libellés français
// ----------------------------------------------------------------
const ACTION_LABELS: Record<string, string> = {
  // Authentification
  LOGIN_SUCCESS:             'Connexion réussie',
  LOGIN_FAILED:              'Connexion échouée',
  LOGIN_LOCKED:              'Compte verrouillé',
  PASSWORD_CHANGED:          'Mot de passe modifié',
  PASSWORD_CHANGE_FAILED:    'Échec changement MDP',
  PASSWORD_RESET_REQUESTED:  'Reset MDP demandé',
  PASSWORD_RESET_SUCCESS:    'Reset MDP réussi',
  PASSWORD_RESET_FAILED:     'Reset MDP échoué',
  '2FA_INITIATED':           '2FA initiée',
  '2FA_ENABLED':             '2FA activée',
  '2FA_DISABLED':            '2FA désactivée',
  '2FA_EMAIL_INITIATED':     '2FA email initiée',
  // Utilisateurs
  USER_CREATED:              'Utilisateur créé',
  USER_DELETED:              'Utilisateur supprimé',
  // Élèves
  STUDENT_CREATED:           'Élève créé',
  STUDENT_UPDATED:           'Élève modifié',
  STUDENT_SOFT_DELETED:      'Élève supprimé',
  STUDENT_DATA_EXPORTED:     'Données élève exportées',
  STUDENTS_IMPORTED:         'Élèves importés',
  STUDENTS_BULK_DELETED:     'Élèves supprimés (lot)',
  // Classes
  CLASS_CREATED:             'Classe créée',
  CLASS_UPDATED:             'Classe modifiée',
  CLASS_DELETED:             'Classe supprimée',
  CLASS_STUDENTS_ASSIGNED:   'Élèves assignés à classe',
  CLASS_STUDENT_REMOVED:     'Élève retiré de classe',
  CLASS_TEACHERS_ASSIGNED:   'Enseignants assignés',
  CLASS_TEACHER_REMOVED:     'Enseignant retiré',
  // Voyages
  TRIP_CREATED:              'Voyage créé',
  TRIP_UPDATED:              'Voyage modifié',
  TRIP_ARCHIVED:             'Voyage archivé',
  // Bracelets
  TOKEN_INITIALIZED:         'Bracelet initialisé',
  TOKEN_ASSIGNED:            'Bracelet assigné',
  TOKEN_REASSIGNED:          'Bracelet réassigné',
  TOKEN_DELETED:             'Bracelet supprimé',
  TOKEN_STATUS_UPDATED:      'Statut bracelet modifié',
  TOKENS_BATCH_INITIALIZED:  'Bracelets initialisés (lot)',
  TOKENS_RELEASED:           'Bracelet libéré',
  // Checkpoints
  CHECKPOINT_CREATED:        'Checkpoint créé',
  CHECKPOINT_CLOSED:         'Checkpoint clôturé',
  // Alertes
  ALERT_CREATED:             'Alerte créée',
  // Exports & Sync
  ATTENDANCES_EXPORTED:      'Présences exportées',
  ATTENDANCES_BULK_EXPORTED:  'Présences exportées (lot)',
  ASSIGNMENTS_EXPORTED:      'Assignations exportées',
  SYNC_ATTENDANCES:          'Présences synchronisées',
  QR_EMAILS_SENT:            'QR codes envoyés par email',
  AUDIT_LOGS_EXPORTED:       'Logs d\'audit exportés',
};

// ----------------------------------------------------------------
// Badge coloré : catégorie + libellé de l'action
// ----------------------------------------------------------------
function getActionBadge(action: string) {
  const label = ACTION_LABELS[action] ?? action;
  const a = action.toLowerCase();

  if (a.includes('login') || a.includes('2fa') || a.includes('password') || a.includes('locked')) {
    return (
      <div className="flex flex-col gap-0.5">
        <Badge className="bg-purple-50 text-purple-700 border-purple-100 hover:bg-purple-50 shadow-none uppercase text-[9px] w-fit">
          Sécurité
        </Badge>
        <span className="text-xs text-slate-700 font-sans">{label}</span>
      </div>
    );
  }
  if (a.includes('created') || a.includes('imported') || a.includes('initialized') || a.includes('assigned')) {
    return (
      <div className="flex flex-col gap-0.5">
        <Badge className="bg-green-50 text-green-700 border-green-100 hover:bg-green-50 shadow-none uppercase text-[9px] w-fit">
          Création
        </Badge>
        <span className="text-xs text-slate-700 font-sans">{label}</span>
      </div>
    );
  }
  if (a.includes('updated') || a.includes('changed') || a.includes('reassigned') || a.includes('closed') || a.includes('released')) {
    return (
      <div className="flex flex-col gap-0.5">
        <Badge className="bg-blue-50 text-blue-700 border-blue-100 hover:bg-blue-50 shadow-none uppercase text-[9px] w-fit">
          Modification
        </Badge>
        <span className="text-xs text-slate-700 font-sans">{label}</span>
      </div>
    );
  }
  if (a.includes('deleted') || a.includes('archived') || a.includes('removed') || a.includes('failed')) {
    return (
      <div className="flex flex-col gap-0.5">
        <Badge className="bg-red-50 text-red-700 border-red-100 hover:bg-red-50 shadow-none uppercase text-[9px] w-fit">
          Suppression
        </Badge>
        <span className="text-xs text-slate-700 font-sans">{label}</span>
      </div>
    );
  }
  if (a.includes('exported') || a.includes('sync') || a.includes('sent')) {
    return (
      <div className="flex flex-col gap-0.5">
        <Badge className="bg-amber-50 text-amber-700 border-amber-100 hover:bg-amber-50 shadow-none uppercase text-[9px] w-fit">
          Export / Sync
        </Badge>
        <span className="text-xs text-slate-700 font-sans">{label}</span>
      </div>
    );
  }
  return (
    <div className="flex flex-col gap-0.5">
      <Badge variant="outline" className="uppercase text-[9px] w-fit">Autre</Badge>
      <span className="text-xs text-slate-700 font-sans">{label}</span>
    </div>
  );
}

// ----------------------------------------------------------------
// Modal détails
// ----------------------------------------------------------------
function DetailsModal({ log, onClose }: { log: AuditLog; onClose: () => void }) {
  const label = ACTION_LABELS[log.action] ?? log.action;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 backdrop-blur-sm p-4">
      <div className="bg-white rounded-2xl shadow-xl w-full max-w-lg max-h-[80vh] flex flex-col">
        {/* Header */}
        <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100">
          <div>
            <h3 className="font-bold text-slate-900 font-heading">{label}</h3>
            <p className="text-xs text-slate-400 font-mono">{log.action}</p>
          </div>
          <button
            onClick={onClose}
            className="p-1.5 rounded-lg hover:bg-slate-100 text-slate-400 hover:text-slate-700 transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
        {/* Contenu */}
        <div className="overflow-y-auto p-6 space-y-4 font-sans text-sm">
          <div className="grid grid-cols-2 gap-x-4 gap-y-2">
            <div className="text-slate-400">Date</div>
            <div className="text-slate-900 font-medium">
              {new Date(log.performed_at).toLocaleString('fr-FR')}
            </div>
            <div className="text-slate-400">Utilisateur</div>
            <div className="text-slate-900 font-medium">{log.user_email ?? '—'}</div>
            {log.user_id && (
              <>
                <div className="text-slate-400">ID utilisateur</div>
                <div className="text-slate-500 font-mono text-xs break-all">{log.user_id}</div>
              </>
            )}
            <div className="text-slate-400">IP</div>
            <div className="text-slate-900 font-mono text-xs">{log.ip_address ?? '—'}</div>
            {log.resource_type && (
              <>
                <div className="text-slate-400">Ressource</div>
                <div className="flex items-center gap-2">
                  <Badge variant="secondary" className="text-[10px]">{log.resource_type}</Badge>
                  {log.resource_id && (
                    <span className="text-slate-400 font-mono text-xs">#{log.resource_id.substring(0, 8)}</span>
                  )}
                </div>
              </>
            )}
            {log.user_agent && (
              <>
                <div className="text-slate-400">User-agent</div>
                <div className="text-slate-500 text-xs break-all">{log.user_agent}</div>
              </>
            )}
          </div>

          {/* Détails JSON formatés */}
          {log.details && Object.keys(log.details).length > 0 && (
            <div>
              <p className="text-xs font-semibold text-slate-500 uppercase tracking-wider mb-2">Détails</p>
              <div className="bg-slate-50 rounded-xl p-3 space-y-1.5">
                {Object.entries(log.details).map(([key, value]) => (
                  <div key={key} className="flex gap-2 text-xs">
                    <span className="text-slate-400 shrink-0 w-32 truncate">{key}</span>
                    <span className="text-slate-700 font-medium break-all">
                      {typeof value === 'object' ? JSON.stringify(value) : String(value)}
                    </span>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
        <div className="px-6 py-4 border-t border-slate-100 flex justify-end">
          <Button variant="outline" size="sm" onClick={onClose} className="rounded-xl">
            Fermer
          </Button>
        </div>
      </div>
    </div>
  );
}

// ----------------------------------------------------------------
// Écran principal
// ----------------------------------------------------------------
export default function AuditLogScreen() {
  const [page, setPage] = useState(1);
  const [actionFilter, setActionFilter] = useState('');
  const [resourceFilter, setResourceFilter] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [isExporting, setIsExporting] = useState(false);
  const [selectedLog, setSelectedLog] = useState<AuditLog | null>(null);

  const filters = {
    action: actionFilter || undefined,
    resource_type: resourceFilter || undefined,
    date_from: startDate || undefined,
    date_to: endDate || undefined,
  };

  const { data, isLoading, error } = useQuery({
    queryKey: ['auditLogs', page, filters],
    queryFn: () => auditApi.getLogs({ page, page_size: 20, ...filters }),
  });

  const handleExport = async () => {
    try {
      setIsExporting(true);
      const blob = await auditApi.exportLogs(filters);
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `audit_logs_${new Date().toISOString().split('T')[0]}.json`;
      link.click();
      window.URL.revokeObjectURL(url);
    } catch {
      alert("Erreur lors de l'exportation des logs.");
    } finally {
      setIsExporting(false);
    }
  };

  const clearFilters = () => {
    setActionFilter('');
    setResourceFilter('');
    setStartDate('');
    setEndDate('');
    setPage(1);
  };

  const hasActiveFilters = !!(actionFilter || resourceFilter || startDate || endDate);

  if (isLoading && !data) return (
    <div className="flex h-64 items-center justify-center">
      <Loader2 className="w-8 h-8 animate-spin text-slate-400" />
      <span className="ml-2 text-slate-500 font-medium font-sans">Chargement des logs...</span>
    </div>
  );

  if (error) return (
    <div className="p-8 bg-red-50 text-schooltrack-error rounded-2xl border border-red-100 flex flex-col items-center gap-4 text-center font-sans">
      <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center">
        <Shield className="w-6 h-6 text-schooltrack-error" />
      </div>
      <div>
        <h3 className="text-lg font-bold">Erreur de chargement</h3>
        <p className="text-sm opacity-80">Impossible de récupérer les journaux d'audit.</p>
      </div>
      <Button variant="outline" onClick={() => window.location.reload()}>Réessayer</Button>
    </div>
  );

  return (
    <div className="space-y-6">
      {/* Modal détails */}
      {selectedLog && (
        <DetailsModal log={selectedLog} onClose={() => setSelectedLog(null)} />
      )}

      {/* En-tête */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">
            Journaux d'Audit
          </h2>
          <p className="text-slate-500 font-sans">
            Suivez l'activité du système et les actions des utilisateurs.
          </p>
        </div>
        <Button
          variant="outline"
          onClick={handleExport}
          disabled={isExporting || data?.items.length === 0}
          className="rounded-xl border-slate-200 gap-2 font-sans bg-white hover:bg-slate-50"
        >
          {isExporting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />}
          <span>Exporter (JSON)</span>
        </Button>
      </div>

      {/* Filtres */}
      <Card className="border-slate-200 shadow-sm bg-white rounded-2xl">
        <CardContent className="p-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4 items-end">

            {/* Filtre Action — toutes les 50 actions groupées */}
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Action</label>
              <select
                value={actionFilter}
                onChange={(e) => { setActionFilter(e.target.value); setPage(1); }}
                className="w-full h-10 px-3 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-primary/20 focus:border-schooltrack-primary font-sans"
              >
                <option value="">Toutes les actions</option>
                <optgroup label="🔐 Authentification">
                  <option value="LOGIN_SUCCESS">Connexion réussie</option>
                  <option value="LOGIN_FAILED">Connexion échouée</option>
                  <option value="LOGIN_LOCKED">Compte verrouillé</option>
                  <option value="PASSWORD_CHANGED">Mot de passe modifié</option>
                  <option value="PASSWORD_CHANGE_FAILED">Échec changement MDP</option>
                  <option value="PASSWORD_RESET_REQUESTED">Reset MDP demandé</option>
                  <option value="PASSWORD_RESET_SUCCESS">Reset MDP réussi</option>
                  <option value="PASSWORD_RESET_FAILED">Reset MDP échoué</option>
                  <option value="2FA_INITIATED">2FA initiée</option>
                  <option value="2FA_ENABLED">2FA activée</option>
                  <option value="2FA_DISABLED">2FA désactivée</option>
                  <option value="2FA_EMAIL_INITIATED">2FA email initiée</option>
                </optgroup>
                <optgroup label="👤 Utilisateurs">
                  <option value="USER_CREATED">Utilisateur créé</option>
                  <option value="USER_DELETED">Utilisateur supprimé</option>
                </optgroup>
                <optgroup label="🎒 Élèves">
                  <option value="STUDENT_CREATED">Élève créé</option>
                  <option value="STUDENT_UPDATED">Élève modifié</option>
                  <option value="STUDENT_SOFT_DELETED">Élève supprimé</option>
                  <option value="STUDENT_DATA_EXPORTED">Données élève exportées</option>
                  <option value="STUDENTS_IMPORTED">Élèves importés</option>
                  <option value="STUDENTS_BULK_DELETED">Élèves supprimés (lot)</option>
                </optgroup>
                <optgroup label="🏫 Classes">
                  <option value="CLASS_CREATED">Classe créée</option>
                  <option value="CLASS_UPDATED">Classe modifiée</option>
                  <option value="CLASS_DELETED">Classe supprimée</option>
                  <option value="CLASS_STUDENTS_ASSIGNED">Élèves assignés à classe</option>
                  <option value="CLASS_STUDENT_REMOVED">Élève retiré de classe</option>
                  <option value="CLASS_TEACHERS_ASSIGNED">Enseignants assignés</option>
                  <option value="CLASS_TEACHER_REMOVED">Enseignant retiré</option>
                </optgroup>
                <optgroup label="🚌 Voyages">
                  <option value="TRIP_CREATED">Voyage créé</option>
                  <option value="TRIP_UPDATED">Voyage modifié</option>
                  <option value="TRIP_ARCHIVED">Voyage archivé</option>
                </optgroup>
                <optgroup label="📿 Bracelets">
                  <option value="TOKEN_INITIALIZED">Bracelet initialisé</option>
                  <option value="TOKEN_ASSIGNED">Bracelet assigné</option>
                  <option value="TOKEN_REASSIGNED">Bracelet réassigné</option>
                  <option value="TOKEN_DELETED">Bracelet supprimé</option>
                  <option value="TOKEN_STATUS_UPDATED">Statut bracelet modifié</option>
                  <option value="TOKENS_BATCH_INITIALIZED">Bracelets initialisés (lot)</option>
                  <option value="TOKENS_RELEASED">Bracelet libéré</option>
                </optgroup>
                <optgroup label="📍 Checkpoints">
                  <option value="CHECKPOINT_CREATED">Checkpoint créé</option>
                  <option value="CHECKPOINT_CLOSED">Checkpoint clôturé</option>
                </optgroup>
                <optgroup label="📤 Exports & Sync">
                  <option value="ATTENDANCES_EXPORTED">Présences exportées</option>
                  <option value="ATTENDANCES_BULK_EXPORTED">Présences exportées (lot)</option>
                  <option value="ASSIGNMENTS_EXPORTED">Assignations exportées</option>
                  <option value="SYNC_ATTENDANCES">Présences synchronisées</option>
                  <option value="QR_EMAILS_SENT">QR codes envoyés</option>
                  <option value="AUDIT_LOGS_EXPORTED">Logs exportés</option>
                </optgroup>
              </select>
            </div>

            {/* Filtre Ressource */}
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Ressource</label>
              <select
                value={resourceFilter}
                onChange={(e) => { setResourceFilter(e.target.value); setPage(1); }}
                className="w-full h-10 px-3 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-primary/20 focus:border-schooltrack-primary font-sans"
              >
                <option value="">Toutes</option>
                <option value="USER">Utilisateur</option>
                <option value="STUDENT">Élève</option>
                <option value="TRIP">Voyage</option>
                <option value="CLASS">Classe</option>
                <option value="TOKEN">Bracelet</option>
                <option value="CHECKPOINT">Checkpoint</option>
              </select>
            </div>

            {/* Dates */}
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Du</label>
              <input
                type="date"
                value={startDate}
                onChange={(e) => { setStartDate(e.target.value); setPage(1); }}
                className="w-full h-10 px-3 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-primary/20 focus:border-schooltrack-primary font-sans"
              />
            </div>
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Au</label>
              <input
                type="date"
                value={endDate}
                onChange={(e) => { setEndDate(e.target.value); setPage(1); }}
                className="w-full h-10 px-3 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-primary/20 focus:border-schooltrack-primary font-sans"
              />
            </div>

            <Button
              variant="ghost"
              onClick={clearFilters}
              disabled={!hasActiveFilters}
              className="h-10 text-slate-500 hover:text-slate-900 hover:bg-slate-100 rounded-xl disabled:opacity-30"
              title="Effacer les filtres"
            >
              <FilterX className="w-4 h-4 mr-2" />
              Réinitialiser
            </Button>
          </div>

          {/* Indicateur filtre actif */}
          {hasActiveFilters && (
            <p className="mt-3 text-xs text-schooltrack-primary font-sans">
              {data?.total ?? '…'} résultat{(data?.total ?? 0) > 1 ? 's' : ''} trouvé{(data?.total ?? 0) > 1 ? 's' : ''}
            </p>
          )}
        </CardContent>
      </Card>

      {/* Table */}
      <Card className="border-slate-200 shadow-sm overflow-hidden bg-white rounded-2xl relative">
        {isLoading && data && (
          <div className="absolute inset-0 bg-white/50 backdrop-blur-sm z-10 flex items-center justify-center">
            <Loader2 className="w-8 h-8 animate-spin text-schooltrack-primary" />
          </div>
        )}
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader className="bg-slate-50/50 font-heading">
                <TableRow className="hover:bg-transparent border-b-slate-100">
                  <TableHead className="min-w-[130px] font-semibold text-schooltrack-primary py-4 px-3 sm:px-6">
                    <div className="flex items-center gap-2"><Calendar className="w-3.5 h-3.5" /> Date & Heure</div>
                  </TableHead>
                  <TableHead className="min-w-[160px] font-semibold text-schooltrack-primary py-4 px-3 sm:px-6">Action</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-3 sm:px-6">
                    <div className="flex items-center gap-2"><User className="w-3.5 h-3.5" /> Utilisateur</div>
                  </TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-3 sm:px-6 text-center">
                    <div className="flex items-center justify-center gap-2"><Globe className="w-3.5 h-3.5" /> IP</div>
                  </TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-3 sm:px-6">Ressource</TableHead>
                  <TableHead className="text-right font-semibold text-schooltrack-primary py-4 px-3 sm:px-6">Détails</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {data?.items.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={6} className="h-48 text-center text-slate-500 italic font-sans">
                      Aucun journal d'audit trouvé pour ces critères.
                    </TableCell>
                  </TableRow>
                ) : (
                  data?.items.map((log) => (
                    <TableRow
                      key={log.id}
                      className="hover:bg-slate-50/50 transition-colors cursor-pointer"
                      onClick={() => setSelectedLog(log)}
                    >
                      <TableCell className="font-medium text-slate-600 py-4 px-3 sm:px-6 font-sans">
                        <div className="flex flex-col">
                          <span>{new Date(log.performed_at).toLocaleDateString('fr-FR')}</span>
                          <span className="text-[10px] text-slate-400">
                            {new Date(log.performed_at).toLocaleTimeString('fr-FR')}
                          </span>
                        </div>
                      </TableCell>
                      <TableCell className="py-4 px-3 sm:px-6">
                        {getActionBadge(log.action)}
                      </TableCell>
                      <TableCell className="py-4 px-3 sm:px-6 font-sans">
                        <div className="flex flex-col">
                          <span className="text-sm text-slate-900 font-bold">
                            {log.user_email ?? 'Système'}
                          </span>
                          {log.user_id && (
                            <span className="text-[10px] text-slate-400 font-mono tracking-tighter">
                              #{log.user_id.substring(0, 8)}
                            </span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-center py-4 px-3 sm:px-6 font-mono text-[11px] text-slate-500">
                        {log.ip_address ?? '—'}
                      </TableCell>
                      <TableCell className="py-4 px-3 sm:px-6 font-sans">
                        <div className="flex items-center gap-2">
                          <Badge
                            variant="secondary"
                            className="font-normal bg-slate-100 text-slate-600 hover:bg-slate-100 border-0 text-[10px]"
                          >
                            {log.resource_type ?? '—'}
                          </Badge>
                          {log.resource_id && (
                            <span className="text-[10px] font-mono text-slate-400 tracking-tighter">
                              #{log.resource_id.substring(0, 8)}
                            </span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-right py-4 px-3 sm:px-6">
                        <span className="text-xs text-slate-400 hover:text-schooltrack-primary transition-colors">
                          Voir →
                        </span>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Pagination */}
      <div className="flex items-center justify-between py-2 font-sans">
        <p className="text-sm text-slate-500">
          Page{' '}
          <span className="font-medium text-slate-900">{data?.page ?? 1}</span> sur{' '}
          <span className="font-medium text-slate-900">{data?.total_pages ?? 1}</span>
          {data?.total != null && (
            <span className="ml-2 text-slate-400">({data.total} entrées)</span>
          )}
        </p>
        <div className="flex gap-2">
          <Button
            variant="outline"
            size="sm"
            className="h-9 px-3 border-slate-200 rounded-lg hover:bg-slate-50 transition-colors disabled:opacity-40"
            disabled={page === 1 || isLoading}
            onClick={() => { setPage(p => p - 1); window.scrollTo({ top: 0, behavior: 'smooth' }); }}
          >
            <ChevronLeft className="w-4 h-4 mr-1" />
            Précédent
          </Button>
          <Button
            variant="outline"
            size="sm"
            className="h-9 px-3 border-slate-200 rounded-lg hover:bg-slate-50 transition-colors disabled:opacity-40"
            disabled={!data || page >= data.total_pages || isLoading}
            onClick={() => { setPage(p => p + 1); window.scrollTo({ top: 0, behavior: 'smooth' }); }}
          >
            Suivant
            <ChevronRight className="w-4 h-4 ml-1" />
          </Button>
        </div>
      </div>
    </div>
  );
}
