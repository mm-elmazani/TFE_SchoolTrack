import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { classApi } from '../api/classApi';
import type { Class } from '../api/classApi';
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
import { Link } from 'react-router-dom';
import { CreateClassDialog } from '../components/CreateClassDialog';
import { UpdateClassDialog } from '../components/UpdateClassDialog';
import { DeleteClassDialog } from '../components/DeleteClassDialog';
import { 
  LayoutGrid, 
  List as ListIcon, 
  Plus, 
  School, 
  ChevronRight,
  Loader2,
  Search,
  Pencil,
  Trash2
} from 'lucide-react';
import { cn } from '@/lib/utils';
import { Badge } from '@/components/ui/badge';

export default function ClassListScreen() {
  const { getIsAdmin } = useAuthStore();
  const isAdmin = getIsAdmin();
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [classToUpdate, setClassToUpdate] = useState<Class | null>(null);
  const [classToDelete, setClassToDelete] = useState<Class | null>(null);
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid');
  const [searchTerm, setSearchTerm] = useState('');

  const { data: classes, isLoading, error } = useQuery({
    queryKey: ['classes'],
    queryFn: classApi.getAll,
  });

  const filteredClasses = classes?.filter(c => 
    c.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
    (c.year && c.year.toLowerCase().includes(searchTerm.toLowerCase()))
  ) || [];

  if (isLoading) return (
    <div className="flex h-64 items-center justify-center">
      <Loader2 className="w-8 h-8 animate-spin text-slate-400" />
      <span className="ml-2 text-slate-500 font-medium">Chargement des classes...</span>
    </div>
  );

  if (error) return (
    <div className="p-8 bg-red-50 text-schooltrack-error rounded-2xl border border-red-100 flex flex-col items-center gap-4 text-center">
      <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center">
        <School className="w-6 h-6 text-schooltrack-error" />
      </div>
      <h3 className="text-lg font-bold">Erreur de chargement</h3>
      <p className="text-sm opacity-80">Impossible de récupérer la liste des classes.</p>
      <Button variant="outline" onClick={() => window.location.reload()}>Réessayer</Button>
    </div>
  );

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary">Classes</h2>
          <p className="text-slate-500">Gérez les classes, les élèves et les enseignants affectés.</p>
        </div>
        {isAdmin && (
          <Button 
            onClick={() => setIsCreateOpen(true)}
            className="bg-schooltrack-action hover:bg-blue-700 text-white rounded-xl h-11 px-6 shadow-md shadow-blue-900/10 flex items-center gap-2 transition-all active:scale-95 border-0"
          >
            <Plus className="w-4 h-4" />
            <span>Nouvelle Classe</span>
          </Button>
        )}
      </div>

      {/* Controls */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div className="relative group flex-1 max-w-md">
          <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-action transition-colors">
            <Search className="h-4 w-4" />
          </div>
          <input 
            type="text" 
            placeholder="Rechercher une classe..." 
            className="w-full pl-10 pr-4 py-2.5 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-action/10 focus:border-schooltrack-action transition-all shadow-sm"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>

        <div className="flex items-center bg-white border border-slate-200 p-1 rounded-xl shadow-sm self-start">
          <button
            onClick={() => setViewMode('grid')}
            className={cn(
              "flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all",
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
              "flex items-center gap-2 px-4 py-2 rounded-lg text-sm font-medium transition-all",
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
      {filteredClasses.length === 0 ? (
        <div className="h-64 flex flex-col items-center justify-center bg-white border-2 border-dashed border-slate-200 rounded-3xl p-12 text-slate-400 text-center">
          <School className="w-12 h-12 opacity-20 mb-4" />
          <p className="text-lg font-medium">Aucune classe trouvée</p>
          <p className="text-sm opacity-60">Modifiez votre recherche ou créez une nouvelle classe.</p>
        </div>
      ) : viewMode === 'grid' ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-6 animate-in fade-in slide-in-from-bottom-4 duration-500">
          {filteredClasses.map((cls) => (
            <div key={cls.id} className="relative group">
              <Link to={`/classes/${cls.id}`}>
                <Card className="h-full border border-slate-200 hover:border-schooltrack-primary/50 hover:shadow-lg hover:shadow-blue-900/5 transition-all duration-300 rounded-2xl bg-white p-5 flex flex-col">
                  <div className="flex justify-between items-start mb-6">
                    <div className="w-10 h-10 bg-slate-50 rounded-xl flex items-center justify-center text-slate-400 group-hover:bg-blue-50 group-hover:text-schooltrack-action transition-colors">
                      <School className="w-5 h-5" />
                    </div>
                    {cls.year && (
                      <Badge variant="outline" className="text-[10px] font-semibold border-slate-100 text-slate-400 bg-slate-50/50 px-2 py-0 h-5">
                        {cls.year}
                      </Badge>
                    )}
                  </div>
                  
                  <div className="mb-6">
                    <h3 className="text-lg font-bold text-slate-900 group-hover:text-schooltrack-primary transition-colors leading-tight">
                      {cls.name}
                    </h3>
                    <p className="text-xs text-slate-400 mt-1 uppercase tracking-widest font-medium font-sans">Classe scolaire</p>
                  </div>

                  <div className="mt-auto pt-4 border-t border-slate-50 flex items-center gap-6">
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 bg-schooltrack-action rounded-full opacity-40" />
                      <span className="text-sm font-bold text-slate-700">{cls.nb_students}</span>
                      <span className="text-[10px] text-slate-400 uppercase font-bold tracking-tighter font-sans">Élèves</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <div className="w-1.5 h-1.5 bg-slate-300 rounded-full opacity-40" />
                      <span className="text-sm font-bold text-slate-700">{cls.nb_teachers}</span>
                      <span className="text-[10px] text-slate-400 uppercase font-bold tracking-tighter font-sans">Profs</span>
                    </div>
                  </div>
                </Card>
              </Link>
              
              {isAdmin && (
                <div className="absolute top-4 right-4 opacity-0 group-hover:opacity-100 transition-opacity flex gap-1">
                  <Button 
                    variant="ghost" 
                    size="icon" 
                    className="h-8 w-8 bg-white/80 backdrop-blur shadow-sm border border-slate-100 rounded-lg text-slate-400 hover:text-schooltrack-primary"
                    onClick={(e) => {
                      e.preventDefault();
                      e.stopPropagation();
                      setClassToUpdate(cls);
                    }}
                  >
                    <Pencil className="w-3.5 h-3.5" />
                  </Button>
                  <Button 
                    variant="ghost" 
                    size="icon" 
                    className="h-8 w-8 bg-white/80 backdrop-blur shadow-sm border border-slate-100 rounded-lg text-slate-400 hover:text-schooltrack-error"
                    onClick={(e) => {
                      e.preventDefault();
                      e.stopPropagation();
                      setClassToDelete(cls);
                    }}
                  >
                    <Trash2 className="w-3.5 h-3.5" />
                  </Button>
                </div>
              )}
            </div>
          ))}
        </div>
      ) : (
        <Card className="border-slate-200 shadow-sm overflow-hidden bg-white animate-in fade-in slide-in-from-bottom-2 duration-500">
          <CardContent className="p-0">
            <div className="overflow-x-auto">
              <Table>
                <TableHeader className="bg-slate-50/50 font-heading">
                  <TableRow className="hover:bg-transparent">
                    <TableHead className="font-semibold text-schooltrack-primary py-4">Nom de la classe</TableHead>
                    <TableHead className="font-semibold text-schooltrack-primary py-4">Année scolaire</TableHead>
                    <TableHead className="font-semibold text-schooltrack-primary py-4 text-center">Effectif</TableHead>
                    <TableHead className="font-semibold text-schooltrack-primary py-4 text-center">Enseignants</TableHead>
                    <TableHead className="text-right font-semibold text-schooltrack-primary py-4">Actions</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {filteredClasses.map((cls) => (
                    <TableRow key={cls.id} className="hover:bg-slate-50/50 transition-colors group">
                      <TableCell className="font-semibold text-slate-900">{cls.name}</TableCell>
                      <TableCell>
                        {cls.year ? (
                          <Badge variant="outline" className="text-slate-500 border-slate-200 font-sans">{cls.year}</Badge>
                        ) : (
                          <span className="text-slate-300 italic text-xs">-</span>
                        )}
                      </TableCell>
                      <TableCell className="text-center font-medium text-slate-600">{cls.nb_students}</TableCell>
                      <TableCell className="text-center font-medium text-slate-600">{cls.nb_teachers}</TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-2">
                          <Link to={`/classes/${cls.id}`}>
                            <Button 
                              variant="ghost" 
                              size="sm" 
                              className="h-9 px-4 text-schooltrack-primary hover:bg-blue-50 rounded-xl flex items-center gap-2"
                            >
                              <span>Gérer</span>
                              <ChevronRight className="w-4 h-4 group-hover:translate-x-1 transition-transform" />
                            </Button>
                          </Link>
                          {isAdmin && (
                            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                              <Button 
                                variant="ghost" 
                                size="icon" 
                                className="h-8 w-8 text-slate-400 hover:text-schooltrack-primary rounded-lg"
                                onClick={() => setClassToUpdate(cls)}
                              >
                                <Pencil className="w-3.5 h-3.5" />
                              </Button>
                              <Button 
                                variant="ghost" 
                                size="icon" 
                                className="h-8 w-8 text-slate-400 hover:text-schooltrack-error rounded-lg"
                                onClick={() => setClassToDelete(cls)}
                              >
                                <Trash2 className="w-3.5 h-3.5" />
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

      <CreateClassDialog open={isCreateOpen} onOpenChange={setIsCreateOpen} />
      <UpdateClassDialog 
        cls={classToUpdate} 
        open={!!classToUpdate} 
        onOpenChange={(open) => !open && setClassToUpdate(null)} 
      />
      <DeleteClassDialog 
        cls={classToDelete} 
        open={!!classToDelete} 
        onOpenChange={(open) => !open && setClassToDelete(null)} 
      />
    </div>
  );
}
