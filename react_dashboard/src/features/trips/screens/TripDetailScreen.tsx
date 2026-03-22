import { useParams, Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { tripApi } from '../api/tripApi';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs';
import { Badge } from '@/components/ui/badge';
import { useAuthStore } from '@/features/auth/store/authStore';
import { useState } from 'react';
import { UpdateTripDialog } from '../components/UpdateTripDialog';
import { 
  ArrowLeft, 
  Calendar, 
  Users, 
  School, 
  CheckCircle2, 
  Clock, 
  FileText, 
  Plus, 
  Trash2,
  Loader2,
  Info,
  Map as MapIcon,
  ChevronRight,
  Activity,
  Pencil
} from 'lucide-react';

export default function TripDetailScreen() {
  const { id } = useParams<{ id: string }>();
  const { getIsAdmin } = useAuthStore();
  const isAdmin = getIsAdmin();
  const [isUpdateOpen, setIsUpdateOpen] = useState(false);

  const { data: trip, isLoading, error } = useQuery({
    queryKey: ['trips', id],
    queryFn: () => tripApi.getById(id!),
    enabled: !!id,
  });

  if (isLoading) return (
    <div className="flex h-screen items-center justify-center">
      <Loader2 className="w-10 h-10 animate-spin text-slate-400" />
    </div>
  );

  if (error || !trip) return (
    <div className="p-8 text-center space-y-4 font-sans">
      <div className="w-16 h-16 bg-red-50 text-schooltrack-error rounded-full flex items-center justify-center mx-auto">
        <Info className="w-8 h-8" />
      </div>
      <h2 className="text-xl font-bold">Voyage introuvable</h2>
      <p className="text-slate-500">Une erreur est survenue lors de la récupération des détails du voyage.</p>
      <Link to="/trips">
        <Button variant="outline">Retour à la liste</Button>
      </Link>
    </div>
  );

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

  return (
    <div className="space-y-8 animate-in fade-in duration-500">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <Link to="/trips">
            <Button variant="ghost" size="sm" className="rounded-full w-10 h-10 p-0 hover:bg-blue-50">
              <ArrowLeft className="w-5 h-5 text-schooltrack-primary" />
            </Button>
          </Link>
          <div>
            <div className="flex items-center gap-3">
              <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">{trip.destination}</h2>
              {getStatusBadge(trip.status)}
            </div>
            <div className="flex items-center gap-4 mt-1 text-slate-500 text-sm font-sans">
              <div className="flex items-center gap-1.5">
                <Calendar className="w-4 h-4 text-schooltrack-action opacity-60" />
                <span>{new Date(trip.date).toLocaleDateString('fr-FR', { dateStyle: 'long' })}</span>
              </div>
              <div className="flex items-center gap-1.5">
                <Users className="w-4 h-4 text-schooltrack-action opacity-60" />
                <span>{trip.total_students} élèves inscrits</span>
              </div>
            </div>
          </div>
        </div>
        <div className="flex items-center gap-2 font-sans">
          {isAdmin && trip.status !== 'ARCHIVED' && (
            <Button 
              variant="outline" 
              className="rounded-xl h-11 border-slate-200 hover:bg-slate-50"
              onClick={() => setIsUpdateOpen(true)}
            >
              <Pencil className="w-4 h-4 mr-2 text-schooltrack-action" />
              Modifier le voyage
            </Button>
          )}
          <Button className="bg-schooltrack-action hover:bg-blue-700 text-white rounded-xl h-11 px-6 shadow-md shadow-blue-900/10 transition-all active:scale-95 border-0">
            <FileText className="w-4 h-4 mr-2" />
            Rapport PDF
          </Button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Main Content (Tabs) */}
        <div className="lg:col-span-2 space-y-6">
          <Tabs defaultValue="classes" className="w-full">
            <TabsList className="w-full justify-start border-b rounded-none h-auto p-0 bg-transparent gap-8">
              <TabsTrigger 
                value="classes" 
                className="data-[state=active]:border-b-2 data-[state=active]:border-schooltrack-primary data-[state=active]:text-schooltrack-primary data-[state=active]:shadow-none rounded-none py-3 px-1 bg-transparent text-slate-500 font-bold transition-all"
              >
                Classes participantes
              </TabsTrigger>
              <TabsTrigger 
                value="checkpoints" 
                className="data-[state=active]:border-b-2 data-[state=active]:border-schooltrack-primary data-[state=active]:text-schooltrack-primary data-[state=active]:shadow-none rounded-none py-3 px-1 bg-transparent text-slate-500 font-bold transition-all"
              >
                Points de contrôle
              </TabsTrigger>
            </TabsList>
            
            <TabsContent value="classes" className="mt-6 animate-in fade-in slide-in-from-left-4 duration-300">
              <Card className="border-slate-200 shadow-sm overflow-hidden bg-white rounded-2xl">
                <CardHeader className="flex flex-row items-center justify-between border-b border-slate-50 bg-slate-50/30">
                  <div className="space-y-1">
                    <CardTitle className="text-lg text-schooltrack-primary font-heading">Classes inscrites</CardTitle>
                    <CardDescription className="font-sans">Liste des classes participant à ce voyage.</CardDescription>
                  </div>
                  {isAdmin && (
                    <Button size="sm" variant="outline" className="rounded-lg h-9 border-slate-200 hover:bg-white hover:text-schooltrack-action font-sans">
                      <Plus className="w-4 h-4 mr-1.5" /> Ajouter
                    </Button>
                  )}
                </CardHeader>
                <CardContent className="p-0 font-sans">
                  {trip.classes.length === 0 ? (
                    <div className="p-12 text-center">
                      <School className="w-12 h-12 text-slate-200 mx-auto mb-3" />
                      <p className="text-slate-500">Aucune classe n'est assignée à ce voyage.</p>
                    </div>
                  ) : (
                    <div className="divide-y divide-slate-50">
                      {trip.classes.map((cls, index) => (
                        <div key={index} className="flex justify-between items-center p-4 hover:bg-slate-50/50 transition-colors group">
                          <div className="flex items-center gap-4">
                            <div className="w-10 h-10 bg-slate-100 rounded-xl flex items-center justify-center text-schooltrack-primary group-hover:bg-blue-50 group-hover:text-schooltrack-action transition-colors">
                              <School className="w-5 h-5" />
                            </div>
                            <div>
                              <div className="flex items-center gap-2">
                                <p className="font-bold text-slate-900">{cls.name}</p>
                                {cls.year && (
                                  <Badge variant="outline" className="text-[10px] py-0 h-4 border-slate-200 text-slate-400 font-normal">
                                    {cls.year}
                                  </Badge>
                                )}
                              </div>
                              <div className="flex items-center gap-2 text-xs text-slate-500 mt-0.5">
                                <Users className="w-3 h-3" />
                                <span>{cls.student_count} élèves</span>
                              </div>
                            </div>
                          </div>
                          <div className="flex items-center gap-2">
                            <Link to={`/classes/${cls.id}`}>
                              <Button variant="ghost" size="sm" className="h-8 w-8 p-0 text-slate-400 hover:text-schooltrack-primary">
                                <ChevronRight className="w-4 h-4" />
                              </Button>
                            </Link>
                            {isAdmin && (
                              <Button variant="ghost" size="sm" className="h-8 w-8 p-0 text-slate-400 hover:text-schooltrack-error hover:bg-red-50">
                                <Trash2 className="w-4 h-4" />
                              </Button>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </CardContent>
              </Card>
            </TabsContent>

            <TabsContent value="checkpoints" className="mt-6 animate-in fade-in slide-in-from-left-4 duration-300">
              <Card className="border-slate-200 shadow-sm bg-white rounded-2xl">
                <CardHeader className="flex flex-row items-center justify-between border-b border-slate-50">
                  <div className="space-y-1">
                    <CardTitle className="text-lg text-schooltrack-primary font-heading">Étapes du voyage</CardTitle>
                    <CardDescription className="font-sans">Points de passage et de validation des présences.</CardDescription>
                  </div>
                  {isAdmin && (
                    <Button size="sm" variant="outline" className="rounded-lg h-9 border-slate-200 font-sans">
                      <Plus className="w-4 h-4 mr-1.5" /> Nouveau point
                    </Button>
                  )}
                </CardHeader>
                <CardContent className="p-12 text-center font-sans">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4">
                    <MapIcon className="w-8 h-8 text-slate-200" />
                  </div>
                  <p className="text-slate-500 font-medium">Gestion des points de contrôle</p>
                  <p className="text-sm text-slate-400 max-w-xs mx-auto mt-1">Configurez les lieux et horaires de scan pour ce voyage spécifique.</p>
                </CardContent>
              </Card>
            </TabsContent>
          </Tabs>
        </div>

        {/* Sidebar Info */}
        <div className="space-y-6 font-sans">
          <Card className="border-slate-200 shadow-sm bg-white overflow-hidden rounded-2xl">
            <div className="h-1.5 bg-schooltrack-action w-full" />
            <CardHeader>
              <CardTitle className="text-lg text-schooltrack-primary flex items-center gap-2 font-heading">
                <Info className="w-4 h-4" /> Résumé du projet
              </CardTitle>
            </CardHeader>
            <CardContent className="space-y-6">
              <div className="space-y-2">
                <p className="text-xs text-slate-400 uppercase font-bold tracking-wider">Description</p>
                <p className="text-sm text-slate-600 leading-relaxed bg-slate-50 p-3 rounded-xl border border-slate-100">
                  {trip.description || "Aucune description détaillée n'a été fournie pour ce voyage scolaire."}
                </p>
              </div>
              
              <div className="grid grid-cols-2 gap-4">
                <div className="bg-blue-50/50 p-4 rounded-2xl border border-blue-100 text-center">
                  <p className="text-[10px] text-schooltrack-action uppercase font-bold tracking-wider mb-1">Total Élèves</p>
                  <p className="text-3xl font-black text-schooltrack-primary font-heading">{trip.total_students}</p>
                </div>
                <div className="bg-green-50/50 p-4 rounded-2xl border border-green-100 text-center">
                  <p className="text-[10px] text-schooltrack-success uppercase font-bold tracking-wider mb-1">Classes</p>
                  <p className="text-3xl font-black text-schooltrack-success font-heading">{trip.classes.length}</p>
                </div>
              </div>

              <div className="pt-4 border-t border-slate-100 space-y-3">
                <p className="text-[10px] text-slate-400 italic">Dernière mise à jour le {new Date(trip.updated_at).toLocaleDateString()}</p>
              </div>
            </CardContent>
          </Card>

          {/* Quick Actions / Tips */}
          <Card className="border-slate-200 shadow-sm bg-schooltrack-primary text-white overflow-hidden rounded-2xl">
            <CardContent className="p-6 space-y-4">
              <div className="w-10 h-10 bg-white/20 rounded-xl flex items-center justify-center">
                <CheckCircle2 className="w-6 h-6 text-white" />
              </div>
              <div className="space-y-1">
                <p className="font-bold text-lg font-heading text-white">Prêt pour le départ ?</p>
                <p className="text-blue-100 text-xs leading-relaxed">
                  Assurez-vous que tous les élèves ont reçu leur bracelet et que les professeurs ont synchronisé l'application mobile.
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>

      <UpdateTripDialog 
        trip={trip}
        open={isUpdateOpen}
        onOpenChange={setIsUpdateOpen}
      />
    </div>
  );
}
