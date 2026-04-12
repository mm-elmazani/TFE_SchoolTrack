import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Link } from 'react-router-dom';
import { tripApi } from '../api/tripApi';
import type { Trip } from '../api/tripApi';
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
import { useAuthStore } from '@/features/auth/store/authStore';
import { useSchoolPath } from '@/hooks/useSchoolPath';
import { CreateTripDialog } from '../components/CreateTripDialog';
import { UpdateTripDialog } from '../components/UpdateTripDialog';
import { ArchiveTripDialog } from '../components/ArchiveTripDialog';
import {
  LayoutGrid,
  List as ListIcon,
  Plus,
  MapPin,
  Calendar,
  ChevronRight,
  Loader2,
  Search,
  Archive,
  Clock,
  CheckCircle2,
  Activity,
  Pencil,
  Download,
  FileArchive,
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select';

export default function TripListScreen() {
  const { getIsAdmin } = useAuthStore();
  const isAdmin = getIsAdmin();
  const sp = useSchoolPath();
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [tripToUpdate, setTripToUpdate] = useState<Trip | null>(null);
  const [tripToArchive, setTripToArchive] = useState<Trip | null>(null);
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
  const [searchTerm, setSearchTerm] = useState('');
  const [statusFilter, setStatusFilter] = useState<string>('ALL');
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());

  const toggleSelect = (id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };

  const downloadWithAuth = (url: string, filename: string) => {
    const token = useAuthStore.getState().token;
    fetch(url, { headers: { Authorization: `Bearer ${token}` } })
      .then(res => res.blob())
      .then(blob => {
        const blobUrl = URL.createObjectURL(blob);
        const a = document.createElement('a');
        a.href = blobUrl;
        a.download = filename;
        a.click();
        URL.revokeObjectURL(blobUrl);
      });
  };

  const handleExportSingle = (trip: Trip) => {
    downloadWithAuth(tripApi.getExportUrl(trip.id), `presences-${trip.destination}.csv`);
  };

  const handleExportBulk = () => {
    if (selectedIds.size === 0) return;
    downloadWithAuth(tripApi.getBulkExportUrl([...selectedIds]), `presences-export.zip`);
  };

  const { data: trips, isLoading, error } = useQuery({
    queryKey: ['trips'],
    queryFn: tripApi.getAll,
  });

  const stats = {
    active: trips?.filter(t => t.status === 'ACTIVE').length || 0,
    upcoming: trips?.filter(t => t.status === 'PLANNED').length || 0,
    completed: trips?.filter(t => t.status === 'COMPLETED').length || 0,
  };

  const filteredTrips = trips?.filter(t => 
    (statusFilter === 'ALL' || t.status === statusFilter) &&
    (t.destination.toLowerCase().includes(searchTerm.toLowerCase()) ||
    (t.description && t.description.toLowerCase().includes(searchTerm.toLowerCase())))
  ) || [];

  const getStatusBadge = (status: string) => {
    switch (status) {
      case 'PLANNED': 
        return <Badge variant="outline" className="bg-blue-50 text-schooltrack-action border-blue-100 gap-1.5 shadow-none font-medium font-sans"><Clock className="w-3 h-3" /> À venir</Badge>;
      case 'ACTIVE': 
        return <Badge className="bg-schooltrack-action text-white border-0 gap-1.5 shadow-md font-bold animate-pulse font-sans"><Activity className="w-3 h-3" /> En cours</Badge>;
      case 'COMPLETED': 
        return <Badge className="bg-schooltrack-success text-white border-0 gap-1.5 shadow-sm font-bold font-sans"><CheckCircle2 className="w-3 h-3" /> Terminé</Badge>;
      case 'ARCHIVED': 
        return <Badge variant="secondary" className="bg-slate-100 text-slate-400 border-0 gap-1.5 uppercase text-[10px] font-sans">Archivé</Badge>;
      default: 
        return <Badge variant="outline">{status}</Badge>;
    }
  };

  if (isLoading) return (
    <div className="flex h-64 items-center justify-center">
      <Loader2 className="w-8 h-8 animate-spin text-slate-400" />
      <span className="ml-2 text-slate-500 font-medium">Chargement des voyages...</span>
    </div>
  );

  if (error) return (
    <div className="p-8 bg-red-50 text-schooltrack-error rounded-2xl border border-red-100 flex flex-col items-center gap-4 text-center font-sans">
      <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center">
        <MapPin className="w-6 h-6 text-schooltrack-error" />
      </div>
      <div>
        <h3 className="text-lg font-bold">Erreur de chargement</h3>
        <p className="text-sm opacity-80">Impossible de récupérer la liste des voyages.</p>
      </div>
      <Button variant="outline" onClick={() => window.location.reload()}>Réessayer</Button>
    </div>
  );

  return (
    <div className="space-y-8 animate-in fade-in duration-500">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">Voyages</h2>
          <p className="text-slate-500 font-sans">Planifiez, gérez et suivez les sorties et voyages scolaires.</p>
        </div>
        <div className="flex items-center gap-3">
          {isAdmin && selectedIds.size > 0 && (
            <Button
              variant="outline"
              onClick={handleExportBulk}
              className="rounded-xl h-11 px-5 flex items-center gap-2 font-sans"
            >
              <FileArchive className="w-4 h-4" />
              <span>Export {selectedIds.size} voyage{selectedIds.size > 1 ? 's' : ''}</span>
            </Button>
          )}
          {isAdmin && (
            <Button
              onClick={() => setIsCreateOpen(true)}
              className="bg-schooltrack-action hover:bg-blue-700 text-white rounded-xl h-11 px-6 shadow-md shadow-blue-900/10 flex items-center gap-2 transition-all active:scale-95 border-0 font-sans"
            >
              <Plus className="w-4 h-4" />
              <span>Nouveau Voyage</span>
            </Button>
          )}
        </div>
      </div>

      {/* Stats Summary */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <Card className="border-slate-200 shadow-sm bg-white overflow-hidden group rounded-2xl">
          <CardContent className="p-4 flex items-center gap-4">
            <div className="w-10 h-10 bg-blue-50 text-schooltrack-action rounded-xl flex items-center justify-center group-hover:scale-110 transition-transform">
              <Activity className="w-5 h-5" />
            </div>
            <div>
              <p className="text-2xl font-black text-slate-900 font-heading">{stats.active}</p>
              <p className="text-[10px] text-slate-400 uppercase font-bold tracking-widest font-sans">En cours</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-slate-200 shadow-sm bg-white overflow-hidden group rounded-2xl">
          <CardContent className="p-4 flex items-center gap-4">
            <div className="w-10 h-10 bg-slate-50 text-slate-400 rounded-xl flex items-center justify-center group-hover:scale-110 transition-transform">
              <Clock className="w-5 h-5" />
            </div>
            <div>
              <p className="text-2xl font-black text-slate-900 font-heading">{stats.upcoming}</p>
              <p className="text-[10px] text-slate-400 uppercase font-bold tracking-widest font-sans">À venir</p>
            </div>
          </CardContent>
        </Card>
        <Card className="border-slate-200 shadow-sm bg-white overflow-hidden group rounded-2xl">
          <CardContent className="p-4 flex items-center gap-4">
            <div className="w-10 h-10 bg-green-50 text-schooltrack-success rounded-xl flex items-center justify-center group-hover:scale-110 transition-transform">
              <CheckCircle2 className="w-5 h-5" />
            </div>
            <div>
              <p className="text-2xl font-black text-slate-900 font-heading">{stats.completed}</p>
              <p className="text-[10px] text-slate-400 uppercase font-bold tracking-widest font-sans">Terminés</p>
            </div>
          </CardContent>
        </Card>
      </div>

      {/* Controls */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="flex flex-col sm:flex-row flex-1 gap-4 max-w-2xl">
          <div className="relative group flex-1">
            <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-action transition-colors">
              <Search className="h-4 w-4" />
            </div>
            <input 
              type="text" 
              placeholder="Rechercher une destination..." 
              className="w-full pl-10 pr-4 py-2.5 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-action/10 focus:border-schooltrack-action transition-all shadow-sm font-sans"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
          
          <Select value={statusFilter} onValueChange={setStatusFilter}>
            <SelectTrigger className="w-full sm:w-[180px] h-[44px] bg-white border-slate-200 rounded-xl font-sans">
              <SelectValue placeholder="Tous les statuts" />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="ALL">Tous les statuts</SelectItem>
              <SelectItem value="PLANNED">À venir</SelectItem>
              <SelectItem value="ACTIVE">En cours</SelectItem>
              <SelectItem value="COMPLETED">Terminés</SelectItem>
              <SelectItem value="ARCHIVED">Archivés</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <div className="flex items-center bg-white border border-slate-200 p-1 rounded-xl shadow-sm self-start">
          <button
            onClick={() => setViewMode('grid')}
            className={cn(
              "flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all font-sans",
              viewMode === 'grid' 
                ? "bg-slate-100 text-schooltrack-primary shadow-inner" 
                : "text-slate-500 hover:text-slate-900 hover:bg-slate-50"
            )}
          >
            <LayoutGrid className="w-4 h-4" />
            <span className="hidden sm:inline">Grille</span>
          </button>
          <button
            onClick={() => setViewMode('list')}
            className={cn(
              "flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all font-sans",
              viewMode === 'list' 
                ? "bg-slate-100 text-schooltrack-primary shadow-inner" 
                : "text-slate-500 hover:text-slate-900 hover:bg-slate-50"
            )}
          >
            <ListIcon className="w-4 h-4" />
            <span className="hidden sm:inline">Liste</span>
          </button>
        </div>
      </div>

      {/* View Content */}
      {filteredTrips.length === 0 ? (
        <div className="h-64 flex flex-col items-center justify-center bg-white border-2 border-dashed border-slate-200 rounded-3xl p-12 text-slate-400 text-center font-sans">
          <MapPin className="w-12 h-12 opacity-20 mb-4" />
          <p className="text-lg font-medium">Aucun voyage trouvé</p>
          <p className="text-sm opacity-60">Modifiez votre recherche ou créez un nouveau projet de voyage.</p>
        </div>
      ) : viewMode === 'grid' ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
          {filteredTrips.map((trip) => (
            <div key={trip.id} className="relative group">
              <Link to={sp(`/trips/${trip.id}`)}>
                <Card className="h-full border border-slate-200 hover:border-schooltrack-primary/50 hover:shadow-lg hover:shadow-blue-900/5 transition-all duration-300 rounded-2xl bg-white p-5 flex flex-col">
                  <div className="flex justify-between items-start mb-6 gap-2">
                    <div className="w-10 h-10 bg-slate-50 rounded-xl flex items-center justify-center text-slate-400 group-hover:bg-blue-50 group-hover:text-schooltrack-action transition-colors shrink-0">
                      <MapPin className="w-5 h-5" />
                    </div>
                    <div className="flex flex-col items-end gap-2 shrink-0">
                      {getStatusBadge(trip.status)}
                      
                      {isAdmin && (
                        <div className="opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 bg-slate-50 border border-slate-100 rounded-lg text-slate-400 hover:text-green-600 hover:bg-white hover:shadow-sm"
                            title="Export CSV"
                            onClick={(e) => { e.preventDefault(); e.stopPropagation(); handleExportSingle(trip); }}
                          >
                            <Download className="w-3 h-3" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 bg-slate-50 border border-slate-100 rounded-lg text-slate-400 hover:text-schooltrack-primary hover:bg-white hover:shadow-sm"
                            onClick={(e) => { e.preventDefault(); e.stopPropagation(); setTripToUpdate(trip); }}
                          >
                            <Pencil className="w-3 h-3" />
                          </Button>
                          <Button
                            variant="ghost"
                            size="icon"
                            className="h-7 w-7 bg-slate-50 border border-slate-100 rounded-lg text-slate-400 hover:text-schooltrack-warning hover:bg-white hover:shadow-sm"
                            onClick={(e) => { e.preventDefault(); e.stopPropagation(); setTripToArchive(trip); }}
                          >
                            <Archive className="w-3 h-3" />
                          </Button>
                        </div>
                      )}
                      {isAdmin && (
                        <label className="flex items-center gap-1 mt-1 cursor-pointer" onClick={(e) => e.stopPropagation()}>
                          <input
                            type="checkbox"
                            checked={selectedIds.has(trip.id)}
                            onChange={(e) => { e.stopPropagation(); toggleSelect(trip.id); }}
                            className="rounded border-slate-300 text-schooltrack-primary"
                          />
                          <span className="text-[10px] text-slate-400">Selectionner</span>
                        </label>
                      )}
                    </div>
                  </div>
                  
                  <div className="mb-6 flex-1">
                    <h3 className="text-xl font-bold text-slate-900 group-hover:text-schooltrack-primary transition-colors leading-tight mb-2 font-heading">
                      {trip.destination}
                    </h3>
                    <p className="text-sm text-slate-500 line-clamp-2 leading-relaxed font-sans">
                      {trip.description || 'Aucune description détaillée.'}
                    </p>
                  </div>

                  <div className="mt-auto pt-4 border-t border-slate-50 flex items-center justify-between font-sans">
                    <div className="flex items-center gap-2 text-slate-400">
                      <Calendar className="w-4 h-4 opacity-60" />
                      <span className="text-xs font-bold uppercase tracking-tighter">
                        {new Date(trip.date).toLocaleDateString('fr-FR', { month: 'short', year: 'numeric' })}
                      </span>
                    </div>
                    <div className="flex items-center gap-1.5 text-schooltrack-primary font-bold text-sm">
                      <span>Détails</span>
                      <ChevronRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                    </div>
                  </div>
                </Card>
              </Link>
            </div>
          ))}
        </div>
      ) : (
        <Card className="border-slate-200 shadow-sm overflow-hidden bg-white animate-in fade-in slide-in-from-bottom-2 duration-500 rounded-2xl">
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <Table>
                <TableHeader className="bg-slate-50/50 font-heading">
                  <TableRow className="hover:bg-transparent border-b-slate-100">
                    <TableHead className="font-semibold text-schooltrack-primary py-4">Destination</TableHead>
                    <TableHead className="font-semibold text-schooltrack-primary py-4">Date</TableHead>
                    <TableHead className="font-semibold text-schooltrack-primary py-4">Statut</TableHead>
                    <TableHead className="text-right font-semibold text-schooltrack-primary py-4">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredTrips.map((trip) => (
                    <TableRow key={trip.id} className="hover:bg-slate-50/50 transition-colors group">
                      <TableCell className="font-semibold text-slate-900">
                        <div className="flex flex-col font-sans">
                          <span className="font-bold">{trip.destination}</span>
                          <span className="text-xs text-slate-400 font-normal line-clamp-1 max-w-xs">{trip.description}</span>
                        </div>
                      </TableCell>
                      <TableCell className="text-sm text-slate-600 font-sans">
                        {new Date(trip.date).toLocaleDateString('fr-FR')}
                      </TableCell>
                      <TableCell>
                        {getStatusBadge(trip.status)}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-2">
                          <Link to={sp(`/trips/${trip.id}`)}>
                            <Button 
                              variant="ghost" 
                              size="sm" 
                              className="h-9 px-4 text-schooltrack-primary hover:bg-blue-50 rounded-xl flex items-center gap-2 font-sans"
                            >
                              <span>Gérer</span>
                              <ChevronRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                            </Button>
                          </Link>
                          {isAdmin && trip.status !== 'ARCHIVED' && (
                            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8 text-slate-400 hover:text-green-600 rounded-lg"
                                title="Export CSV"
                                onClick={() => handleExportSingle(trip)}
                              >
                                <Download className="w-3.5 h-3.5" />
                              </Button>
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8 text-slate-400 hover:text-schooltrack-primary rounded-lg"
                                title="Modifier"
                                onClick={() => setTripToUpdate(trip)}
                              >
                                <Pencil className="w-3.5 h-3.5" />
                              </Button>
                              <Button
                                variant="ghost"
                                size="icon"
                                className="h-8 w-8 text-slate-400 hover:text-schooltrack-warning rounded-lg"
                                title="Archiver"
                                onClick={() => setTripToArchive(trip)}
                              >
                                <Archive className="w-3.5 h-3.5" />
                              </Button>
                            </div>
                          )}
                        </div>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </CardContent>
        </Card>
      )}

      <CreateTripDialog open={isCreateOpen} onOpenChange={setIsCreateOpen} />
      <UpdateTripDialog 
        trip={tripToUpdate} 
        open={!!tripToUpdate} 
        onOpenChange={(open) => !open && setTripToUpdate(null)} 
      />
      <ArchiveTripDialog 
        trip={tripToArchive} 
        open={!!tripToArchive} 
        onOpenChange={(open) => !open && setTripToArchive(null)} 
      />
    </div>
  );
}
