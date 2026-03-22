import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { tokenApi, type TripStudentInfo } from '../api/tokenApi';
import { tripApi } from '@/features/trips/api/tripApi';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { useState } from 'react';
import { useAuthStore } from '@/features/auth/store/authStore';
import { 
  Rss, 
  MapPin, 
  Users, 
  CheckCircle, 
  AlertTriangle, 
  Trash2, 
  Loader2, 
  ChevronRight, 
  RefreshCw, 
  Download, 
  Mail, 
  Search,
  CheckCircle2,
  X
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';
import { 
  Table, 
  TableBody, 
  TableCell, 
  TableHead, 
  TableHeader, 
  TableRow 
} from '@/components/ui/table';
import { AssignTokenDialog } from '../components/AssignTokenDialog';

export default function TokenManagementScreen() {
  const { getIsAdmin } = useAuthStore();
  const isAdmin = getIsAdmin();
  const queryClient = useQueryClient();
  const [selectedTripId, setSelectedTripId] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [studentToAssign, setStudentToAssign] = useState<TripStudentInfo | null>(null);
  const [isReassign, setIsReassign] = useState(false);
  const [actionFeedback, setActionFeedback] = useState<{ type: 'success' | 'error', message: string } | null>(null);

  // Fetch trips
  const { data: trips, isLoading: isLoadingTrips, error: errorTrips, refetch: refetchTrips } = useQuery({
    queryKey: ['trips'],
    queryFn: tripApi.getAll,
  });

  const activeTrips = trips?.filter(t => t.status !== 'ARCHIVED') || [];

  // Fetch students for selected trip
  const { data: tripData, isLoading: isLoadingStudents, isFetching: isFetchingStudents, refetch: refetchStudents } = useQuery({
    queryKey: ['tokens', 'students', selectedTripId],
    queryFn: () => tokenApi.getTripStudents(selectedTripId!),
    enabled: !!selectedTripId,
  });

  const releaseMutation = useMutation({
    mutationFn: tokenApi.releaseTripTokens,
    onSuccess: (data) => {
      setActionFeedback({ 
        type: 'success', 
        message: `${data.released_count} bracelets libérés avec succès.` 
      });
      queryClient.invalidateQueries({ queryKey: ['tokens', 'students', selectedTripId] });
      setTimeout(() => setActionFeedback(null), 5000);
    },
    onError: () => {
      setActionFeedback({ type: 'error', message: "Erreur lors de la libération des bracelets." });
    }
  });

  const sendQrMutation = useMutation({
    mutationFn: tokenApi.sendQrEmails,
    onSuccess: (data) => {
      setActionFeedback({ 
        type: 'success', 
        message: `${data.sent_count} emails envoyés avec succès.` 
      });
      queryClient.invalidateQueries({ queryKey: ['tokens', 'students', selectedTripId] });
      setTimeout(() => setActionFeedback(null), 5000);
    },
    onError: () => {
      setActionFeedback({ type: 'error', message: "Erreur lors de l'envoi des emails." });
    }
  });

  const filteredStudents = tripData?.students.filter(s => 
    `${s.first_name} ${s.last_name}`.toLowerCase().includes(searchTerm.toLowerCase()) ||
    (s.token_uid && s.token_uid.toLowerCase().includes(searchTerm.toLowerCase()))
  ) || [];

  const handleExport = () => {
    if (!selectedTripId) return;
    const url = tokenApi.getExportUrl(selectedTripId);
    window.open(url, '_blank');
  };

  const getAssignmentBadge = (type: string | null) => {
    if (!type) return null;
    switch (type) {
      case 'NFC_PHYSICAL': return <Badge variant="outline" className="bg-blue-50 text-blue-700 border-blue-100 text-[10px]">NFC</Badge>;
      case 'QR_PHYSICAL': return <Badge variant="outline" className="bg-purple-50 text-purple-700 border-purple-100 text-[10px]">QR Phys.</Badge>;
      case 'QR_DIGITAL': return <Badge variant="outline" className="bg-teal-50 text-teal-700 border-teal-100 text-[10px]">QR Digital</Badge>;
      default: return <Badge variant="outline" className="text-[10px]">{type}</Badge>;
    }
  };

  if (isLoadingTrips) return (
    <div className="flex h-64 items-center justify-center">
      <Loader2 className="w-8 h-8 animate-spin text-slate-400" />
      <span className="ml-2 text-slate-500 font-medium font-sans">Chargement des voyages...</span>
    </div>
  );

  if (errorTrips) return (
    <div className="p-8 bg-red-50 text-schooltrack-error rounded-2xl border border-red-100 flex flex-col items-center gap-4 text-center font-sans">
      <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center">
        <MapPin className="w-6 h-6 text-schooltrack-error" />
      </div>
      <div>
        <h3 className="text-lg font-bold font-heading text-schooltrack-primary">Erreur de chargement</h3>
        <p className="text-sm opacity-80">Impossible de récupérer la liste des voyages.</p>
      </div>
      <Button variant="outline" onClick={() => refetchTrips()}>Réessayer</Button>
    </div>
  );

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">Gestion des Bracelets</h2>
          <p className="text-slate-500 font-sans">Attribuez les supports NFC/QR et gérez les envois de codes digitaux.</p>
        </div>
        
        {selectedTripId && (
          <div className="flex items-center gap-2">
            <Button 
              variant="outline" 
              size="icon" 
              className="rounded-xl border-slate-200"
              onClick={() => refetchStudents()}
              disabled={isFetchingStudents}
            >
              <RefreshCw className={cn("w-4 h-4", isFetchingStudents && "animate-spin")} />
            </Button>
            <Button 
              variant="outline" 
              className="rounded-xl border-slate-200 gap-2 font-sans"
              onClick={handleExport}
            >
              <Download className="w-4 h-4" />
              <span>Export CSV</span>
            </Button>
            {isAdmin && (
              <>
                <Button 
                  className="bg-teal-600 hover:bg-teal-700 text-white rounded-xl gap-2 font-sans border-0 shadow-md"
                  onClick={() => {
                    if(confirm("Envoyer les QR codes digitaux par email à tous les élèves du voyage ?")) {
                      sendQrMutation.mutate(selectedTripId);
                    }
                  }}
                  disabled={sendQrMutation.isPending}
                >
                  <Mail className="w-4 h-4" />
                  <span>Envoyer QR</span>
                </Button>
                <Button 
                  variant="destructive"
                  className="rounded-xl gap-2 font-sans bg-schooltrack-error hover:bg-red-700 border-0 shadow-md"
                  onClick={() => {
                    if(confirm("Libérer TOUS les bracelets de ce voyage ?")) {
                      releaseMutation.mutate(selectedTripId);
                    }
                  }}
                  disabled={releaseMutation.isPending}
                >
                  <Trash2 className="w-4 h-4" />
                  <span>Libérer Tout</span>
                </Button>
              </>
            )}
          </div>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-4 gap-8">
        {/* Trip Selector */}
        <Card className="lg:col-span-1 border-slate-200 shadow-sm h-fit bg-white rounded-2xl overflow-hidden">
          <CardHeader className="pb-4 bg-slate-50/50 border-b border-slate-100">
            <CardTitle className="text-sm font-bold text-schooltrack-primary font-heading flex items-center gap-2 uppercase tracking-wider">
              <MapPin className="w-4 h-4" /> Voyages
            </CardTitle>
          </CardHeader>
          <CardContent className="p-2">
            {activeTrips.length === 0 ? (
              <div className="p-6 text-center text-sm text-slate-400 italic font-sans">Aucun voyage disponible</div>
            ) : (
              <div className="space-y-1">
                {activeTrips.map(trip => (
                  <button 
                    key={trip.id}
                    className={cn(
                      "w-full flex items-center justify-between px-4 py-3 rounded-xl text-sm font-medium transition-all font-sans",
                      selectedTripId === trip.id 
                        ? "bg-schooltrack-primary text-white shadow-md shadow-blue-900/20" 
                        : "text-slate-600 hover:bg-blue-50 hover:text-schooltrack-primary"
                    )}
                    onClick={() => setSelectedTripId(trip.id)}
                  >
                    <span className="truncate">{trip.destination}</span>
                    <ChevronRight className={cn("w-4 h-4", selectedTripId === trip.id ? "opacity-100" : "opacity-0 group-hover:opacity-100")} />
                  </button>
                ))}
              </div>
            )}
          </CardContent>
        </Card>

        {/* Content Area */}
        <div className="lg:col-span-3 space-y-6">
          {selectedTripId ? (
            <div className="space-y-6 animate-in fade-in slide-in-from-right-4 duration-500">
              {/* Action Feedback Banner */}
              {actionFeedback && (
                <div className={cn(
                  "p-4 rounded-xl text-sm flex items-center justify-between animate-in fade-in zoom-in duration-300",
                  actionFeedback.type === 'success' ? "bg-green-50 text-schooltrack-success border border-green-100" : "bg-red-50 text-schooltrack-error border border-red-100"
                )}>
                  <div className="flex items-center gap-3">
                    {actionFeedback.type === 'success' ? <CheckCircle2 className="w-5 h-5" /> : <AlertTriangle className="w-5 h-5" />}
                    <span className="font-medium">{actionFeedback.message}</span>
                  </div>
                  <button onClick={() => setActionFeedback(null)} className="hover:opacity-70 transition-opacity">
                    <X className="w-4 h-4" />
                  </button>
                </div>
              )}

              {/* Stats Grid */}
              <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 font-sans">
                <Card className="border-slate-200 shadow-sm bg-white rounded-2xl overflow-hidden">
                  <div className="h-1 bg-slate-200" />
                  <CardContent className="p-6 flex items-center gap-4">
                    <div className="w-10 h-10 bg-slate-50 rounded-xl flex items-center justify-center text-slate-400">
                      <Users className="w-5 h-5" />
                    </div>
                    <div>
                      <p className="text-2xl font-black text-slate-900 font-heading">{tripData?.total || 0}</p>
                      <p className="text-[10px] text-slate-400 uppercase font-bold tracking-widest">Total</p>
                    </div>
                  </CardContent>
                </Card>

                <Card className="border-slate-200 shadow-sm bg-white rounded-2xl overflow-hidden">
                  <div className="h-1 bg-schooltrack-success" />
                  <CardContent className="p-6 flex items-center gap-4">
                    <div className="w-10 h-10 bg-green-50 rounded-xl flex items-center justify-center text-schooltrack-success">
                      <CheckCircle className="w-5 h-5" />
                    </div>
                    <div>
                      <p className="text-2xl font-black text-slate-900 font-heading">{tripData?.assigned || 0}</p>
                      <p className="text-[10px] text-slate-400 uppercase font-bold tracking-widest">Assignés</p>
                    </div>
                  </CardContent>
                </Card>

                <Card className="border-slate-200 shadow-sm bg-white rounded-2xl overflow-hidden">
                  <div className="h-1 bg-schooltrack-warning" />
                  <CardContent className="p-6 flex items-center gap-4">
                    <div className="w-10 h-10 bg-orange-50 rounded-xl flex items-center justify-center text-schooltrack-warning">
                      <Rss className="w-5 h-5" />
                    </div>
                    <div>
                      <p className="text-2xl font-black text-slate-900 font-heading">{tripData?.unassigned || 0}</p>
                      <p className="text-[10px] text-slate-400 uppercase font-bold tracking-widest">Non assignés</p>
                    </div>
                  </CardContent>
                </Card>
              </div>

              {/* Search Bar */}
              <div className="relative group max-w-md">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400 group-focus-within:text-schooltrack-action transition-colors" />
                <input 
                  type="text" 
                  placeholder="Rechercher un élève ou un UID..." 
                  className="w-full pl-10 pr-4 py-2.5 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-action/10 focus:border-schooltrack-action transition-all shadow-sm font-sans"
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                />
              </div>

              {/* Students Table */}
              <Card className="border-slate-200 shadow-sm overflow-hidden bg-white rounded-2xl">
                <CardContent className="p-0">
                  <div className="overflow-x-auto">
                    <Table>
                      <TableHeader className="bg-slate-50/50">
                        <TableRow className="hover:bg-transparent border-b-slate-100">
                          <TableHead className="font-semibold text-schooltrack-primary py-4 px-6">Nom</TableHead>
                          <TableHead className="font-semibold text-schooltrack-primary py-4 px-6">Prénom</TableHead>
                          <TableHead className="font-semibold text-schooltrack-primary py-4 px-6">Token UID</TableHead>
                          <TableHead className="font-semibold text-schooltrack-primary py-4 px-6 text-center">Type</TableHead>
                          <TableHead className="text-right font-semibold text-schooltrack-primary py-4 px-6">Action</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {isLoadingStudents ? (
                          <TableRow>
                            <TableCell colSpan={5} className="h-48 text-center">
                              <Loader2 className="w-8 h-8 animate-spin mx-auto text-slate-200" />
                            </TableCell>
                          </TableRow>
                        ) : filteredStudents.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={5} className="h-48 text-center text-slate-400 italic font-sans">
                              Aucun élève trouvé
                            </TableCell>
                          </TableRow>
                        ) : (
                          filteredStudents.map((student) => (
                            <TableRow key={student.id} className="hover:bg-slate-50/50 transition-colors group">
                              <TableCell className="font-bold text-slate-900 py-4 px-6 font-sans uppercase text-xs tracking-tight">{student.last_name}</TableCell>
                              <TableCell className="text-slate-600 py-4 px-6 font-sans">{student.first_name}</TableCell>
                              <TableCell className="py-4 px-6">
                                {student.token_uid ? (
                                  <code className="text-[11px] bg-slate-100 px-2 py-1 rounded font-mono text-slate-600">
                                    {student.token_uid}
                                  </code>
                                ) : (
                                  <span className="text-slate-300 italic text-[11px]">—</span>
                                )}
                              </TableCell>
                              <TableCell className="text-center py-4 px-6">
                                {getAssignmentBadge(student.assignment_type)}
                              </TableCell>
                              <TableCell className="text-right py-4 px-6">
                                {isAdmin && (
                                  <Button 
                                    variant={student.token_uid ? "ghost" : "outline"}
                                    size="sm"
                                    className={cn(
                                      "h-8 px-3 rounded-lg text-[11px] font-bold uppercase tracking-wider transition-all font-sans",
                                      student.token_uid 
                                        ? "text-slate-400 hover:text-schooltrack-primary hover:bg-blue-50" 
                                        : "bg-schooltrack-action text-white hover:bg-blue-700 border-0 shadow-sm"
                                    )}
                                    onClick={() => {
                                      setIsReassign(!!student.token_uid);
                                      setStudentToAssign(student);
                                    }}
                                  >
                                    {student.token_uid ? 'Réassigner' : 'Assigner'}
                                  </Button>
                                )}
                              </TableCell>
                            </TableRow>
                          ))
                        )}
                      </TableBody>
                    </Table>
                  </div>
                </CardContent>
              </Card>
            </div>
          ) : (
            <div className="h-64 flex flex-col items-center justify-center border-2 border-dashed border-slate-200 rounded-3xl p-12 text-slate-400 text-center animate-in fade-in duration-700 bg-white/50 font-sans">
              <div className="w-16 h-16 bg-white rounded-2xl shadow-sm flex items-center justify-center mb-4 text-slate-300">
                <Rss className="w-8 h-8 opacity-20" />
              </div>
              <p className="text-lg font-bold text-slate-900">Sélectionnez un voyage</p>
              <p className="text-sm opacity-60 max-w-xs mt-1">Choisissez un voyage dans la liste à gauche pour gérer les bracelets des élèves.</p>
            </div>
          )}
        </div>
      </div>

      <AssignTokenDialog 
        student={studentToAssign}
        tripId={selectedTripId}
        open={!!studentToAssign}
        onOpenChange={(open) => !open && setStudentToAssign(null)}
        isReassign={isReassign}
      />
    </div>
  );
}
