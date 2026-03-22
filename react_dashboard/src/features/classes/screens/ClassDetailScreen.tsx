import { useParams, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { classApi } from '../api/classApi';
import { studentApi } from '@/features/students/api/studentApi';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { useAuthStore } from '@/features/auth/store/authStore';
import { useState, useEffect } from 'react';
import {
  ArrowLeft,
  Users,
  Mail,
  UserPlus,
  Plus,
  Trash2,
  Loader2,
  School,
  Calendar,
  Search,
  X,
  CheckCircle2,
  ChevronRight,
  AlertTriangle
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';

export default function ClassDetailScreen() {
  const { id } = useParams<{ id: string }>();
  const { getIsAdmin } = useAuthStore();
  const isAdmin = getIsAdmin();
  const queryClient = useQueryClient();
  const [searchTerm, setSearchTerm] = useState('');
  const [lastAssignedName, setLastAssignedName] = useState<string | null>(null);

  const { data: cls, isLoading: isLoadingClass } = useQuery({
    queryKey: ['classes', id],
    queryFn: () => classApi.getById(id!),
    enabled: !!id,
  });

  const { data: classStudentIds, isLoading: isLoadingStudentIds } = useQuery({
    queryKey: ['classes', id, 'students'],
    queryFn: () => classApi.getStudents(id!),
    enabled: !!id,
  });

  const { data: allStudents, isLoading: isLoadingAllStudents } = useQuery({
    queryKey: ['students'],
    queryFn: studentApi.getAll,
  });

  // Fetch all classes to detect students already assigned elsewhere
  const { data: allClasses } = useQuery({
    queryKey: ['classes'],
    queryFn: classApi.getAll,
  });

  // Build a map of studentId → className for students in OTHER classes
  const [studentClassMap, setStudentClassMap] = useState<Map<string, string>>(new Map());

  useEffect(() => {
    if (!allClasses || !id) return;
    const otherClasses = allClasses.filter(c => c.id !== id);
    if (otherClasses.length === 0) {
      setStudentClassMap(new Map());
      return;
    }
    let cancelled = false;
    const fetchMemberships = async () => {
      const map = new Map<string, string>();
      await Promise.all(
        otherClasses.map(async (cls) => {
          try {
            const studentIds = await classApi.getStudents(cls.id);
            studentIds.forEach((sid: string) => map.set(sid, cls.name));
          } catch { /* ignore errors for individual classes */ }
        })
      );
      if (!cancelled) setStudentClassMap(map);
    };
    fetchMemberships();
    return () => { cancelled = true; };
  }, [allClasses, id]);

  const handleAssignStudent = (student: { id: string; first_name: string; last_name: string }) => {
    const existingClass = studentClassMap.get(student.id);
    if (existingClass) {
      if (!confirm(`${student.first_name} ${student.last_name} est déjà assigné(e) à la classe "${existingClass}".\n\nVoulez-vous quand même l'assigner à cette classe ?`)) {
        return;
      }
    }
    assignStudentMutation.mutate({ id: student.id, name: `${student.first_name} ${student.last_name}` });
  };

  const assignStudentMutation = useMutation({
    mutationFn: (student: { id: string, name: string }) => classApi.assignStudents(id!, [student.id]),
    onSuccess: (_, variables) => {
      setLastAssignedName(variables.name);
      queryClient.invalidateQueries({ queryKey: ['classes', id] });
      queryClient.invalidateQueries({ queryKey: ['classes', id, 'students'] });
      setTimeout(() => setLastAssignedName(null), 3000);
    }
  });

  const removeStudentMutation = useMutation({
    mutationFn: (studentId: string) => classApi.removeStudent(id!, studentId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['classes', id] });
      queryClient.invalidateQueries({ queryKey: ['classes', id, 'students'] });
    }
  });

  const [isAssigning, setIsAssigning] = useState(false);

  if (isLoadingClass || isLoadingStudentIds || isLoadingAllStudents) {
    return (
      <div className="flex h-screen items-center justify-center">
        <Loader2 className="w-10 h-10 animate-spin text-slate-400" />
      </div>
    );
  }

  if (!cls) {
    return (
      <div className="p-8 text-center space-y-4">
        <div className="w-16 h-16 bg-red-50 text-schooltrack-error rounded-full flex items-center justify-center mx-auto">
          <School className="w-8 h-8" />
        </div>
        <h2 className="text-xl font-bold">Classe introuvable</h2>
        <Link to="/classes">
          <Button variant="outline">Retour à la liste</Button>
        </Link>
      </div>
    );
  }

  const enrolledStudents = allStudents?.filter(s => classStudentIds?.includes(s.id)) || [];
  const availableStudents = allStudents?.filter(s => !classStudentIds?.includes(s.id)) || [];
  
  const filteredAvailable = availableStudents.filter(s => 
    `${s.first_name} ${s.last_name}`.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="space-y-8 animate-in fade-in duration-500">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <Link to="/classes">
            <Button variant="ghost" size="sm" className="rounded-full w-10 h-10 p-0 hover:bg-blue-50">
              <ArrowLeft className="w-5 h-5 text-schooltrack-primary" />
            </Button>
          </Link>
          <div>
            <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary">{cls.name}</h2>
            <div className="flex items-center gap-3 mt-1">
              <Badge variant="outline" className="text-slate-500 border-slate-200">
                {cls.year || 'Année non spécifiée'}
              </Badge>
              <span className="text-xs text-slate-400 flex items-center gap-1">
                <Users className="w-3 h-3" /> {cls.nb_students} élèves
              </span>
            </div>
          </div>
        </div>
        {isAdmin && (
          <Button 
            onClick={() => setIsAssigning(!isAssigning)}
            variant={isAssigning ? "outline" : "default"}
            className={cn(
              "rounded-xl h-11 px-6 shadow-md transition-all active:scale-95 border-0",
              isAssigning 
                ? "bg-white border border-slate-200 text-slate-600 hover:bg-slate-50" 
                : "bg-schooltrack-action hover:bg-blue-700 text-white"
            )}
          >
            {isAssigning ? <X className="w-4 h-4 mr-2" /> : <UserPlus className="w-4 h-4 mr-2" />}
            <span>{isAssigning ? 'Annuler' : 'Assigner des élèves'}</span>
          </Button>
        )}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        <div className="lg:col-span-2 space-y-6">
          {isAssigning && isAdmin && (
            <Card className="border-schooltrack-action/30 shadow-lg shadow-blue-900/5 bg-blue-50/30 overflow-hidden animate-in slide-in-from-top-4 duration-300">
              <CardHeader className="pb-4">
                <CardTitle className="text-lg text-schooltrack-primary">Sélectionner des élèves</CardTitle>
                <CardDescription>Ajoutez des élèves existants à cette classe.</CardDescription>
                
                {lastAssignedName && (
                  <div className="mt-4 p-3 bg-green-50 text-schooltrack-success border border-green-100 rounded-xl text-sm flex items-center gap-2 animate-in fade-in zoom-in duration-300">
                    <CheckCircle2 className="w-4 h-4" />
                    <span>L'élève <strong>{lastAssignedName}</strong> a été ajouté avec succès !</span>
                  </div>
                )}

                <div className="relative mt-4">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-slate-400" />
                  <input 
                    type="text" 
                    placeholder="Filtrer par nom..." 
                    className="w-full pl-10 pr-4 py-2 bg-white border border-slate-200 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-action/20 focus:border-schooltrack-action transition-all"
                    value={searchTerm}
                    onChange={(e) => setSearchTerm(e.target.value)}
                  />
                </div>
              </CardHeader>
              <CardContent>
                <div className="grid grid-cols-1 md:grid-cols-2 gap-3 max-h-[300px] overflow-y-auto pr-2 custom-scrollbar">
                  {filteredAvailable.length === 0 ? (
                    <p className="col-span-full text-center py-8 text-sm text-slate-400 italic">Aucun élève disponible</p>
                  ) : (
                    filteredAvailable.map(student => {
                      const existingClass = studentClassMap.get(student.id);
                      return (
                        <div key={student.id} className={cn(
                          "flex justify-between items-center p-3 bg-white border rounded-xl hover:border-schooltrack-action/50 transition-all group",
                          existingClass ? "border-orange-200" : "border-slate-100"
                        )}>
                          <div className="flex flex-col">
                            <span className="font-semibold text-slate-900 text-sm">{student.last_name} {student.first_name}</span>
                            {existingClass ? (
                              <span className="text-[10px] text-orange-500 font-semibold flex items-center gap-1">
                                <AlertTriangle className="w-3 h-3" /> Déjà dans : {existingClass}
                              </span>
                            ) : (
                              <span className="text-[10px] text-slate-400 uppercase tracking-tighter">Disponible</span>
                            )}
                          </div>
                          <Button
                            size="sm"
                            variant="ghost"
                            className="h-8 w-8 p-0 text-schooltrack-action hover:bg-blue-50 rounded-lg disabled:opacity-50"
                            disabled={assignStudentMutation.isPending}
                            onClick={() => handleAssignStudent(student)}
                          >
                            {assignStudentMutation.isPending && assignStudentMutation.variables?.id === student.id ? (
                              <Loader2 className="w-4 h-4 animate-spin" />
                            ) : (
                              <Plus className="w-4 h-4" />
                            )}
                          </Button>
                        </div>
                      );
                    })
                  )}
                </div>
              </CardContent>
            </Card>
          )}

          <Card className="border-slate-200 shadow-sm overflow-hidden bg-white">
            <CardHeader className="bg-slate-50/50 border-b border-slate-100 flex flex-row items-center justify-between py-4">
              <div className="space-y-0.5">
                <CardTitle className="text-lg text-schooltrack-primary">Élèves de la classe</CardTitle>
                <CardDescription className="text-xs">Liste nominative des inscrits.</CardDescription>
              </div>
              <Badge className="bg-schooltrack-primary/10 text-schooltrack-primary hover:bg-schooltrack-primary/10 shadow-none border-0">
                {enrolledStudents.length} membres
              </Badge>
            </CardHeader>
            <CardContent className="p-0">
              {enrolledStudents.length === 0 ? (
                <div className="p-12 text-center">
                  <Users className="w-12 h-12 text-slate-200 mx-auto mb-3" />
                  <p className="text-slate-500">Cette classe ne contient aucun élève pour le moment.</p>
                </div>
              ) : (
                <div className="divide-y divide-slate-50">
                  {enrolledStudents.map((student) => (
                    <div key={student.id} className="flex justify-between items-center p-4 hover:bg-slate-50/50 transition-colors group">
                      <div className="flex items-center gap-4">
                        <div className="w-10 h-10 bg-slate-100 rounded-full flex items-center justify-center text-schooltrack-primary group-hover:bg-white group-hover:shadow-sm transition-all font-bold text-xs">
                          {student.first_name[0]}{student.last_name[0]}
                        </div>
                        <div>
                          <p className="font-bold text-slate-900">{student.last_name} {student.first_name}</p>
                          <div className="flex items-center gap-2 text-xs text-slate-500">
                            <Mail className="w-3.5 h-3.5 opacity-40" />
                            <span>{student.email || 'Pas d\'email renseigné'}</span>
                          </div>
                        </div>
                      </div>
                      <div className="flex items-center gap-2">
                        <Link to={`/students/${student.id}`}>
                          <Button variant="ghost" size="sm" className="h-9 w-9 p-0 text-slate-400 hover:text-schooltrack-primary rounded-lg">
                            <ChevronRight className="w-4 h-4" />
                          </Button>
                        </Link>
                        {isAdmin && (
                          <Button 
                            variant="ghost" 
                            size="sm" 
                            className="h-9 w-9 p-0 text-slate-400 hover:text-schooltrack-error hover:bg-red-50 rounded-lg"
                            onClick={() => {
                              if (confirm(`Retirer ${student.first_name} ${student.last_name} de la classe ?`)) {
                                removeStudentMutation.mutate(student.id);
                              }
                            }}
                            disabled={removeStudentMutation.isPending}
                          >
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
        </div>

        <div className="space-y-6">
          <Card className="border-slate-200 shadow-sm bg-white overflow-hidden">
            <div className="h-1.5 bg-schooltrack-primary w-full" />
            <CardHeader>
              <CardTitle className="text-lg text-schooltrack-primary">Récapitulatif</CardTitle>
            </CardHeader>
            <CardContent className="p-6 space-y-6">
              <div className="space-y-4">
                <div className="flex items-start gap-3">
                  <div className="w-8 h-8 bg-blue-50 rounded-lg flex items-center justify-center text-schooltrack-action shrink-0">
                    <Users className="w-4 h-4" />
                  </div>
                  <div>
                    <p className="text-xs text-slate-400 uppercase font-bold tracking-wider">Effectif Total</p>
                    <p className="text-2xl font-black text-schooltrack-primary">{cls.nb_students}</p>
                  </div>
                </div>
                
                <div className="flex items-start gap-3">
                  <div className="w-8 h-8 bg-green-50 rounded-lg flex items-center justify-center text-schooltrack-success shrink-0">
                    <CheckCircle2 className="w-4 h-4" />
                  </div>
                  <div>
                    <p className="text-xs text-slate-400 uppercase font-bold tracking-wider">Enseignants</p>
                    <p className="text-2xl font-black text-schooltrack-success">{cls.nb_teachers}</p>
                  </div>
                </div>

                <div className="flex items-start gap-3">
                  <div className="w-8 h-8 bg-slate-50 rounded-lg flex items-center justify-center text-slate-400 shrink-0">
                    <Calendar className="w-4 h-4" />
                  </div>
                  <div>
                    <p className="text-xs text-slate-400 uppercase font-bold tracking-wider">Créée le</p>
                    <p className="text-sm font-semibold text-slate-700">{new Date(cls.created_at).toLocaleDateString('fr-FR', { dateStyle: 'long' })}</p>
                  </div>
                </div>
              </div>

              <div className="pt-6 border-t border-slate-100">
                <p className="text-xs text-slate-400 leading-relaxed italic">
                  Les élèves ajoutés à cette classe seront automatiquement disponibles pour les voyages auxquels la classe est inscrite.
                </p>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
