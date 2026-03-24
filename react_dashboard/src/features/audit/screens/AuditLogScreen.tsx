import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { auditApi } from '../api/auditApi';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { 
  Table, 
  TableBody, 
  TableCell, 
  TableHead, 
  TableHeader, 
  TableRow 
} from '@/components/ui/table';
import { Badge } from '@/components/ui/badge';
import { Calendar, User, Shield, Info, ChevronLeft, ChevronRight, Loader2, Globe, Download, FilterX } from 'lucide-react';

export default function AuditLogScreen() {
  const [page, setPage] = useState(1);
  const [actionFilter, setActionFilter] = useState('');
  const [resourceFilter, setResourceFilter] = useState('');
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [isExporting, setIsExporting] = useState(false);

  const filters = {
    action: actionFilter || undefined,
    resource_type: resourceFilter || undefined,
    start_date: startDate || undefined,
    end_date: endDate || undefined,
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
      link.setAttribute('download', `audit_logs_${new Date().toISOString().split('T')[0]}.csv`);
      document.body.appendChild(link);
      link.click();
      link.parentNode?.removeChild(link);
    } catch (err) {
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
        <p className="text-sm opacity-80">Impossible de récupérer les journaux d'audit pour le moment.</p>
      </div>
      <Button variant="outline" onClick={() => window.location.reload()}>Réessayer</Button>
    </div>
  );

  const getActionBadge = (action: string) => {
    const actionLower = action.toLowerCase();
    if (actionLower.includes('create') || actionLower.includes('add')) return <Badge className="bg-green-50 text-schooltrack-success border-green-100 hover:bg-green-50 shadow-none uppercase text-[10px] font-sans">Création</Badge>;
    if (actionLower.includes('update') || actionLower.includes('edit')) return <Badge className="bg-blue-50 text-schooltrack-action border-blue-100 hover:bg-blue-50 shadow-none uppercase text-[10px] font-sans">Modification</Badge>;
    if (actionLower.includes('delete') || actionLower.includes('remove')) return <Badge className="bg-red-50 text-schooltrack-error border-red-100 hover:bg-red-50 shadow-none uppercase text-[10px] font-sans">Suppression</Badge>;
    if (actionLower.includes('login') || actionLower.includes('auth')) return <Badge className="bg-purple-50 text-purple-700 border-purple-100 hover:bg-purple-50 shadow-none uppercase text-[10px] font-sans">Sécurité</Badge>;
    return <Badge variant="outline" className="uppercase text-[10px] font-sans">{action}</Badge>;
  };

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">Journaux d'Audit</h2>
          <p className="text-slate-500 font-sans">Suivez l'activité du système et les actions des utilisateurs.</p>
        </div>
        <Button 
          variant="outline"
          onClick={handleExport}
          disabled={isExporting || (data?.items.length === 0 && !isLoading)}
          className="rounded-xl border-slate-200 gap-2 font-sans bg-white hover:bg-slate-50"
        >
          {isExporting ? <Loader2 className="w-4 h-4 animate-spin" /> : <Download className="w-4 h-4" />}
          <span>Exporter (JSON/CSV)</span>
        </Button>
      </div>

      {/* Filters */}
      <Card className="border-slate-200 shadow-sm bg-white rounded-2xl">
        <CardContent className="p-4">
          <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-5 gap-4 items-end">
            <div className="flex flex-col gap-1.5">
              <label className="text-xs font-semibold text-slate-500 uppercase tracking-wider">Action</label>
              <select
                value={actionFilter}
                onChange={(e) => { setActionFilter(e.target.value); setPage(1); }}
                className="w-full h-10 px-3 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-primary/20 focus:border-schooltrack-primary font-sans"
              >
                <option value="">Toutes</option>
                <option value="LOGIN_SUCCESS">Login Succès</option>
                <option value="LOGIN_FAILED">Login Échoué</option>
                <option value="STUDENT_CREATED">Création Élève</option>
                <option value="STUDENT_UPDATED">Modif. Élève</option>
                <option value="STUDENT_DELETED">Suppr. Élève</option>
                <option value="TRIP_CREATED">Création Voyage</option>
                <option value="TOKEN_ASSIGNED">Assignation Bracelet</option>
              </select>
            </div>
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
              </select>
            </div>
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
              className="h-10 text-slate-500 hover:text-slate-900 hover:bg-slate-100 rounded-xl"
              title="Effacer les filtres"
            >
              <FilterX className="w-4 h-4 mr-2" />
              Réinitialiser
            </Button>
          </div>
        </CardContent>
      </Card>

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
                  <TableHead className="w-[180px] font-semibold text-schooltrack-primary py-4 px-6">
                    <div className="flex items-center gap-2"><Calendar className="w-3.5 h-3.5" /> Date & Heure</div>
                  </TableHead>
                  <TableHead className="w-[150px] font-semibold text-schooltrack-primary py-4 px-6">Action</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6">
                    <div className="flex items-center gap-2"><User className="w-3.5 h-3.5" /> Utilisateur</div>
                  </TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 text-center">
                    <div className="flex items-center justify-center gap-2"><Globe className="w-3.5 h-3.5" /> IP</div>
                  </TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4 px-6">Ressource</TableHead>
                  <TableHead className="text-right font-semibold text-schooltrack-primary py-4 px-6">Détails</TableHead>
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
                    <TableRow key={log.id} className="hover:bg-slate-50/50 transition-colors group">
                      <TableCell className="font-medium text-slate-600 py-4 px-6 font-sans">
                        <div className="flex flex-col">
                          <span>{new Date(log.performed_at).toLocaleDateString('fr-FR')}</span>
                          <span className="text-[10px] text-slate-400">{new Date(log.performed_at).toLocaleTimeString('fr-FR')}</span>
                        </div>
                      </TableCell>
                      <TableCell className="py-4 px-6">
                        {getActionBadge(log.action)}
                      </TableCell>
                      <TableCell className="py-4 px-6 font-sans">
                        <div className="flex flex-col">
                          <span className="text-sm text-slate-900 font-bold" title={log.user_id || 'Système'}>
                            {log.user_email || 'Système'}
                          </span>
                          {log.user_id && (
                            <span className="text-[10px] text-slate-400 font-mono tracking-tighter">#{log.user_id.substring(0,8)}</span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-center py-4 px-6 font-mono text-[11px] text-slate-500">
                        {log.ip_address || '—'}
                      </TableCell>
                      <TableCell className="py-4 px-6 font-sans">
                        <div className="flex items-center gap-2">
                          <Badge variant="secondary" className="font-normal bg-slate-100 text-slate-600 hover:bg-slate-100 border-0 text-[10px]">
                            {log.resource_type || '—'}
                          </Badge>
                          {log.resource_id && (
                            <span className="text-[10px] font-mono text-slate-400 tracking-tighter">
                              #{log.resource_id.substring(0,8)}
                            </span>
                          )}
                        </div>
                      </TableCell>
                      <TableCell className="text-right py-4 px-6">
                        <Button 
                          variant="ghost" 
                          size="sm" 
                          className="h-8 px-2 text-slate-400 hover:text-schooltrack-primary rounded-lg" 
                          title={JSON.stringify(log.details, null, 2)}
                        >
                          <Info className="w-4 h-4" />
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      {/* Pagination moderne */}
      <div className="flex items-center justify-between py-2 font-sans">
        <p className="text-sm text-slate-500">
          Page <span className="font-medium text-slate-900">{data?.page || 1}</span> sur <span className="font-medium text-slate-900">{data?.total_pages || 1}</span>
        </p>
        <div className="flex gap-2">
          <Button 
            variant="outline" 
            size="sm"
            className="h-9 px-3 border-slate-200 rounded-lg hover:bg-slate-50 transition-colors disabled:opacity-40"
            disabled={page === 1 || isLoading}
            onClick={() => {
              setPage(p => p - 1);
              window.scrollTo({ top: 0, behavior: 'smooth' });
            }}
          >
            <ChevronLeft className="w-4 h-4 mr-1" />
            Précédent
          </Button>
          <Button 
            variant="outline" 
            size="sm"
            className="h-9 px-3 border-slate-200 rounded-lg hover:bg-slate-50 transition-colors disabled:opacity-40"
            disabled={!data || page >= data.total_pages || isLoading}
            onClick={() => {
              setPage(p => p + 1);
              window.scrollTo({ top: 0, behavior: 'smooth' });
            }}
          >
            Suivant
            <ChevronRight className="w-4 h-4 ml-1" />
          </Button>
        </div>
      </div>
    </div>
  );
}
