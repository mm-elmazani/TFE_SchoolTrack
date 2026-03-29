import { useParams, Link } from 'react-router-dom';
import { useSchoolPath } from '@/hooks/useSchoolPath';
import { useQuery } from '@tanstack/react-query';
import { studentApi } from '../api/studentApi';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { 
  ArrowLeft, 
  User, 
  Mail, 
  School, 
  Calendar, 
  Rss, 
  CheckCircle2, 
  XCircle,
  Loader2,
  Download
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';

export default function StudentDetailScreen() {
  const { id } = useParams<{ id: string }>();
  const sp = useSchoolPath();

  const { data, isLoading, error } = useQuery({
    queryKey: ['student', id],
    queryFn: () => studentApi.getGdprExport(id!),
    enabled: !!id,
  });

  if (isLoading) return (
    <div className="flex h-screen items-center justify-center">
      <Loader2 className="w-10 h-10 animate-spin text-slate-400" />
    </div>
  );

  if (error || !data) return (
    <div className="p-8 text-center space-y-4">
      <div className="w-16 h-16 bg-red-50 text-red-500 rounded-full flex items-center justify-center mx-auto">
        <XCircle className="w-8 h-8" />
      </div>
      <h2 className="text-xl font-bold">Élève introuvable</h2>
      <p className="text-slate-500">Une erreur est survenue lors de la récupération du profil.</p>
      <Link to={sp('/students')}>
        <Button variant="outline">Retour à la liste</Button>
      </Link>
    </div>
  );

  const { student, classes, attendances, assignments } = data;

  const handleDownloadJson = () => {
    const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.setAttribute('download', `profil_${student.last_name}_${student.first_name}.json`);
    document.body.appendChild(link);
    link.click();
    link.parentNode?.removeChild(link);
  };

  return (
    <div className="space-y-8 animate-in fade-in duration-500">
      {/* Header */}
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div className="flex items-center gap-4">
          <Link to={sp('/students')}>
            <Button variant="ghost" size="sm" className="rounded-full w-10 h-10 p-0 hover:bg-blue-50">
              <ArrowLeft className="w-5 h-5 text-schooltrack-primary" />
            </Button>
          </Link>
          <div>
            <h2 className="text-3xl font-bold tracking-tight text-schooltrack-primary">
              {student.first_name} {student.last_name}
            </h2>
            <div className="flex items-center gap-2 mt-1">
              <Badge variant="outline" className="text-[10px] font-mono border-slate-200 text-slate-400">
                ID: {student.id}
              </Badge>
              {student.is_deleted && (
                <Badge variant="destructive" className="text-[10px] uppercase bg-schooltrack-error text-white border-0">Supprimé (RGPD)</Badge>
              )}
            </div>
          </div>
        </div>
        <Button 
          variant="outline" 
          onClick={handleDownloadJson}
          className="rounded-xl h-11 border-slate-200 flex items-center gap-2 hover:bg-slate-50"
        >
          <Download className="w-4 h-4 text-schooltrack-action" />
          <span>Exporter Profil</span>
        </Button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">
        {/* Left Column: Summary & Classes */}
        <div className="space-y-8">
          {/* Personal Info */}
          <Card className="border-slate-200 shadow-sm overflow-hidden bg-white">
            <CardHeader className="bg-slate-50/50 border-b border-slate-100">
              <CardTitle className="text-lg flex items-center gap-2 text-schooltrack-primary">
                <User className="w-4 h-4" /> Informations
              </CardTitle>
            </CardHeader>
            <CardContent className="p-6 space-y-4">
              <div className="space-y-1">
                <p className="text-xs text-slate-400 uppercase font-semibold tracking-wider">Email</p>
                <div className="flex items-center gap-2 text-slate-700">
                  <Mail className="w-4 h-4 text-schooltrack-action opacity-60" />
                  <span>{student.email || 'Non renseigné'}</span>
                </div>
              </div>
              <div className="space-y-1">
                <p className="text-xs text-slate-400 uppercase font-semibold tracking-wider">Date d'inscription</p>
                <div className="flex items-center gap-2 text-slate-700">
                  <Calendar className="w-4 h-4 text-schooltrack-action opacity-60" />
                  <span>{new Date(student.created_at).toLocaleDateString('fr-FR', { dateStyle: 'long' })}</span>
                </div>
              </div>
              <div className="pt-4 border-t border-slate-100">
                <div className="flex items-center justify-between">
                  <span className="text-sm font-medium text-slate-600">Consentement Photo</span>
                  {student.parent_consent ? (
                    <Badge className="bg-green-100 text-schooltrack-success border-green-200 hover:bg-green-100">Accordé</Badge>
                  ) : (
                    <Badge variant="outline" className="text-slate-400 border-slate-200">Non renseigné</Badge>
                  )}
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Classes */}
          <Card className="border-slate-200 shadow-sm bg-white">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2 text-schooltrack-primary">
                <School className="w-4 h-4" /> Classes
              </CardTitle>
              <CardDescription>Classes auxquelles appartient l'élève.</CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              {classes.length === 0 ? (
                <div className="p-6 text-center text-sm text-slate-400 italic">Aucune classe enregistrée</div>
              ) : (
                <div className="divide-y divide-slate-100">
                  {classes.map((c: any) => (
                    <div key={c.class_id} className="p-4 flex items-center justify-between">
                      <span className="font-semibold text-slate-900">{c.class_name}</span>
                      <span className="text-xs text-slate-400">Depuis le {new Date(c.enrolled_at).toLocaleDateString()}</span>
                    </div>
                  ))}
                </div>
              )}
            </CardContent>
          </Card>
        </div>

        {/* Right Column: History & Attendance */}
        <div className="lg:col-span-2 space-y-8">
          {/* Assignments (Tokens) */}
          <Card className="border-slate-200 shadow-sm bg-white">
            <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
              <div className="space-y-1">
                <CardTitle className="text-lg flex items-center gap-2 text-schooltrack-primary">
                  <Rss className="w-4 h-4" /> Bracelets (NFC/QR)
                </CardTitle>
                <CardDescription>Historique des tokens assignés.</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-slate-50/50 border-y border-slate-100">
                    <tr>
                      <th className="px-6 py-3 text-left font-semibold text-schooltrack-primary">Token UID</th>
                      <th className="px-6 py-3 text-left font-semibold text-schooltrack-primary">Type</th>
                      <th className="px-6 py-3 text-left font-semibold text-schooltrack-primary">Statut</th>
                      <th className="px-6 py-3 text-right font-semibold text-schooltrack-primary">Assigné le</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {assignments.length === 0 ? (
                      <tr>
                        <td colSpan={4} className="px-6 py-8 text-center text-slate-400 italic">Aucun bracelet historisé</td>
                      </tr>
                    ) : (
                      assignments.map((as: any) => (
                        <tr key={as.id} className="hover:bg-slate-50/30 transition-colors">
                          <td className="px-6 py-4 font-mono text-xs">{as.token_uid}</td>
                          <td className="px-6 py-4">
                            <Badge variant="secondary" className="bg-blue-50 text-schooltrack-action text-[10px] uppercase border-blue-100 shadow-none">{as.assignment_type}</Badge>
                          </td>
                          <td className="px-6 py-4">
                            {as.released_at ? (
                              <Badge variant="outline" className="text-slate-400 border-slate-200">Libéré</Badge>
                            ) : (
                              <Badge className="bg-blue-100 text-schooltrack-primary border-blue-200">Actif</Badge>
                            )}
                          </td>
                          <td className="px-6 py-4 text-right text-slate-500">
                            {new Date(as.assigned_at).toLocaleDateString()}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>

          {/* Attendances (Presence) */}
          <Card className="border-slate-200 shadow-sm bg-white">
            <CardHeader>
              <CardTitle className="text-lg flex items-center gap-2 text-schooltrack-primary">
                <CheckCircle2 className="w-4 h-4" /> Historique des Présences
              </CardTitle>
              <CardDescription>Derniers scans effectués en voyage.</CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="bg-slate-50/50 border-y border-slate-100">
                    <tr>
                      <th className="px-6 py-3 text-left font-semibold text-schooltrack-primary">Date & Heure</th>
                      <th className="px-6 py-3 text-left font-semibold text-schooltrack-primary">Méthode</th>
                      <th className="px-6 py-3 text-left font-semibold text-schooltrack-primary">Manuel</th>
                      <th className="px-6 py-3 text-right font-semibold text-schooltrack-primary">Détails</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-slate-100">
                    {attendances.length === 0 ? (
                      <tr>
                        <td colSpan={4} className="px-6 py-8 text-center text-slate-400 italic">Aucun scan enregistré</td>
                      </tr>
                    ) : (
                      attendances.reverse().slice(0, 10).map((att: any) => (
                        <tr key={att.id} className="hover:bg-slate-50/30 transition-colors">
                          <td className="px-6 py-4">
                            <div className="flex flex-col">
                              <span className="font-medium text-slate-900">{new Date(att.scanned_at).toLocaleString('fr-FR', { dateStyle: 'short', timeStyle: 'short' })}</span>
                            </div>
                          </td>
                          <td className="px-6 py-4">
                            <Badge variant="outline" className="text-[10px] uppercase font-semibold text-schooltrack-action border-blue-100">
                              {att.scan_method}
                            </Badge>
                          </td>
                          <td className="px-6 py-4 text-center">
                            {att.is_manual ? (
                              <CheckCircle2 className="w-4 h-4 text-schooltrack-warning mx-auto" />
                            ) : (
                              <span className="text-slate-300">-</span>
                            )}
                          </td>
                          <td className="px-6 py-4 text-right text-xs text-slate-500 max-w-[150px] truncate" title={att.justification || att.comment}>
                            {att.justification || att.comment || '-'}
                          </td>
                        </tr>
                      ))
                    )}
                  </tbody>
                </table>
              </div>
            </CardContent>
          </Card>
        </div>
      </div>
    </div>
  );
}
