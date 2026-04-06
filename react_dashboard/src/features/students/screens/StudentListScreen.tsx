import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { studentApi } from '../api/studentApi';
import type { Student } from '../api/studentApi';
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
import { Link, useNavigate } from 'react-router-dom';
import { useSchoolPath } from '@/hooks/useSchoolPath';
import { useAuthStore } from '@/features/auth/store/authStore';
import { CreateStudentDialog } from '../components/CreateStudentDialog';
import { UpdateStudentDialog } from '../components/UpdateStudentDialog';
import { DeleteStudentDialog } from '../components/DeleteStudentDialog';
import { 
  Plus, 
  Upload, 
  Search, 
  Pencil, 
  Trash2, 
  Download, 
  Eye, 
  User, 
  Mail, 
  Loader2,
  MoreHorizontal,
  RefreshCw
} from 'lucide-react';
import { cn } from '@/lib/utils';

export default function StudentListScreen() {
  const { getIsAdmin } = useAuthStore();
  const isAdmin = getIsAdmin();
  const navigate = useNavigate();
  const sp = useSchoolPath();
  const [isCreateOpen, setIsCreateOpen] = useState(false);
  const [studentToUpdate, setStudentToUpdate] = useState<Student | null>(null);
  const [studentToDelete, setStudentToDelete] = useState<Student | null>(null);
  const [searchTerm, setSearchTerm] = useState('');

  const { data: students, isLoading, error, refetch, isFetching } = useQuery({
    queryKey: ['students'],
    queryFn: studentApi.getAll,
  });

  const handleExportGdpr = async (student: Student) => {
    try {
      const data = await studentApi.getGdprExport(student.id);
      const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
      const url = window.URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = `export_rgpd_${student.last_name}_${student.first_name}.json`;
      link.click();
      window.URL.revokeObjectURL(url);
    } catch (err) {
      alert("Erreur lors de l'exportation des données.");
    }
  };

  const filteredStudents = students?.filter(s => 
    `${s.first_name} ${s.last_name}`.toLowerCase().includes(searchTerm.toLowerCase()) ||
    s.email?.toLowerCase().includes(searchTerm.toLowerCase())
  ) || [];

  if (isLoading) return (
    <div className="flex h-64 items-center justify-center">
      <Loader2 className="w-8 h-8 animate-spin text-slate-400" />
      <span className="ml-2 text-slate-500 font-medium">Chargement des élèves...</span>
    </div>
  );

  if (error) return (
    <div className="p-8 bg-red-50 text-red-700 rounded-2xl border border-red-100 flex flex-col items-center gap-4 text-center">
      <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center">
        <User className="w-6 h-6 text-red-600" />
      </div>
      <div>
        <h3 className="text-lg font-bold">Erreur de chargement</h3>
        <p className="text-sm opacity-80">Impossible de récupérer la liste des élèves.</p>
      </div>
      <Button variant="outline" onClick={() => window.location.reload()}>Réessayer</Button>
    </div>
  );

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex flex-col gap-1">
          <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary font-heading">Élèves</h2>
          <p className="text-slate-500">Gérez la base de données des élèves et leurs informations personnelles.</p>
        </div>
        {isAdmin && (
          <div className="flex items-center gap-2">
            <Link to={sp('/students/import')}>
              <Button variant="outline" className="rounded-xl h-11 border-slate-200 flex items-center gap-2 hover:bg-slate-50">
                <Upload className="w-4 h-4" />
                <span className="hidden sm:inline">Importer CSV</span>
              </Button>
            </Link>
            <Button 
              onClick={() => setIsCreateOpen(true)}
              className="bg-schooltrack-action hover:bg-blue-700 text-white rounded-xl h-11 px-6 shadow-md shadow-blue-900/10 flex items-center gap-2 transition-all active:scale-95 border-0"
            >
              <Plus className="w-4 h-4" />
              <span>Ajouter un élève</span>
            </Button>
          </div>
        )}
      </div>

      <div className="flex items-center gap-4 max-w-2xl">
        <div className="relative group flex-1">
          <div className="absolute inset-y-0 left-0 flex items-center pl-3 pointer-events-none text-slate-400 group-focus-within:text-schooltrack-action transition-colors">
            <Search className="h-4 w-4" />
          </div>
          <input 
            type="text" 
            placeholder="Rechercher un élève par nom ou email..." 
            className="w-full pl-10 pr-4 py-2.5 bg-white border border-slate-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-schooltrack-action/10 focus:border-schooltrack-action transition-all shadow-sm"
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
          />
        </div>
        <Button 
          variant="outline" 
          size="icon" 
          onClick={() => refetch()} 
          disabled={isFetching}
          className="rounded-xl h-11 w-11 border-slate-200 bg-white shadow-sm hover:bg-slate-50 transition-all active:scale-95"
          title="Actualiser la liste"
        >
          <RefreshCw className={cn("h-4 w-4 text-slate-600", isFetching && "animate-spin")} />
        </Button>
      </div>

      <Card className="border-slate-200 shadow-sm overflow-hidden bg-white">
        <CardContent className="p-0">
          <div className="overflow-x-auto">
            <Table>
              <TableHeader className="bg-slate-50/50">
                <TableRow className="hover:bg-transparent border-b-slate-100">
                  <TableHead className="font-semibold text-schooltrack-primary py-4">Élève</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4">Contact</TableHead>
                  <TableHead className="font-semibold text-schooltrack-primary py-4">Inscrit le</TableHead>
                  <TableHead className="text-right font-semibold text-schooltrack-primary py-4">Actions</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {filteredStudents.length === 0 ? (
                  <TableRow>
                    <TableCell colSpan={4} className="h-48 text-center text-slate-500 italic">
                      {searchTerm ? 'Aucun résultat pour votre recherche' : 'Aucun élève trouvé dans la base'}
                    </TableCell>
                  </TableRow>
                ) : (
                  filteredStudents.map((student) => (
                    <TableRow key={student.id} className="hover:bg-slate-50/50 transition-colors group">
                      <TableCell className="font-medium">
                        <div className="flex items-center gap-3">
                          <div className="w-9 h-9 bg-slate-100 rounded-full flex items-center justify-center text-slate-600 font-bold text-xs group-hover:bg-white group-hover:shadow-sm transition-all">
                            {student.first_name[0]}{student.last_name[0]}
                          </div>
                          <div className="flex flex-col">
                            <span className="text-slate-900 font-semibold">{student.last_name} {student.first_name}</span>
                            <span className="text-[10px] text-slate-400 font-mono tracking-tighter">#{student.id.substring(0,8)}</span>
                          </div>
                        </div>
                      </TableCell>
                      <TableCell>
                        {student.email ? (
                          <div className="flex items-center gap-2 text-slate-600">
                            <Mail className="w-3.5 h-3.5 opacity-40" />
                            <span className="text-sm">{student.email}</span>
                          </div>
                        ) : (
                          <span className="text-slate-300 text-xs italic">Non renseigné</span>
                        )}
                      </TableCell>
                      <TableCell className="text-sm text-slate-500">
                        {new Date(student.created_at).toLocaleDateString('fr-FR')}
                      </TableCell>
                      <TableCell className="text-right">
                        <div className="flex items-center justify-end gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                          <Button 
                            variant="ghost" 
                            size="sm" 
                            className="h-9 w-9 p-0 text-slate-500 hover:text-slate-900 hover:bg-white hover:shadow-sm rounded-lg"
                            title="Voir les détails"
                            onClick={() => navigate(sp(`/students/${student.id}`))}
                          >
                            <Eye className="w-4 h-4" />
                          </Button>
                          
                          <Button 
                            variant="ghost" 
                            size="sm" 
                            className="h-9 w-9 p-0 text-slate-500 hover:text-blue-600 hover:bg-blue-50 rounded-lg"
                            title="Exporter RGPD (JSON)"
                            onClick={() => handleExportGdpr(student)}
                          >
                            <Download className="w-4 h-4" />
                          </Button>

                          {isAdmin && (
                            <>
                              <Button 
                                variant="ghost" 
                                size="sm" 
                                className="h-9 w-9 p-0 text-slate-500 hover:text-indigo-600 hover:bg-indigo-50 rounded-lg"
                                title="Modifier"
                                onClick={() => setStudentToUpdate(student)}
                              >
                                <Pencil className="w-4 h-4" />
                              </Button>
                              <Button 
                                variant="ghost" 
                                size="sm" 
                                className="h-9 w-9 p-0 text-red-400 hover:text-red-600 hover:bg-red-50 rounded-lg"
                                title="Supprimer"
                                onClick={() => setStudentToDelete(student)}
                              >
                                <Trash2 className="w-4 h-4" />
                              </Button>
                            </>
                          )}
                        </div>
                        {/* Fallback for touch devices or visible by default if needed */}
                        <div className="sm:hidden">
                          <Button variant="ghost" size="sm" className="h-8 w-8 p-0">
                            <MoreHorizontal className="w-4 h-4" />
                          </Button>
                        </div>
                      </TableCell>
                    </TableRow>
                  ))
                )}
              </TableBody>
            </Table>
          </div>
        </CardContent>
      </Card>

      <CreateStudentDialog open={isCreateOpen} onOpenChange={setIsCreateOpen} />
      
      <UpdateStudentDialog 
        student={studentToUpdate}
        open={!!studentToUpdate}
        onOpenChange={(open) => !open && setStudentToUpdate(null)}
      />

      <DeleteStudentDialog 
        student={studentToDelete} 
        open={!!studentToDelete} 
        onOpenChange={(open) => !open && setStudentToDelete(null)} 
      />
    </div>
  );
}
