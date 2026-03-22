import { useQuery } from '@tanstack/react-query';
import { useAuthStore } from '@/features/auth/store/authStore';
import { Card } from '@/components/ui/card';
import { studentApi } from '@/features/students/api/studentApi';
import { classApi } from '@/features/classes/api/classApi';
import { tripApi } from '@/features/trips/api/tripApi';
import { 
  Users, 
  MapPin, 
  Rss, 
  Upload, 
  UserCog, 
  ShieldCheck,
  School,
  Activity,
  Loader2
} from 'lucide-react';
import { Link } from 'react-router-dom';
import { cn } from '@/lib/utils';

export default function DashboardScreen() {
  const { user, getIsAdmin } = useAuthStore();
  const isAdmin = getIsAdmin();

  // Fetch data for KPIs
  const { data: students, isLoading: loadingStudents } = useQuery({ queryKey: ['students'], queryFn: studentApi.getAll });
  const { data: classes, isLoading: loadingClasses } = useQuery({ queryKey: ['classes'], queryFn: classApi.getAll });
  const { data: trips, isLoading: loadingTrips } = useQuery({ queryKey: ['trips'], queryFn: tripApi.getAll });

  const activeTripsCount = trips?.filter(t => t.status === 'ACTIVE' || t.status === 'PLANNED').length || 0;

  const kpiCards = [
    { 
      title: 'Total Élèves', 
      value: loadingStudents ? <Loader2 className="w-5 h-5 animate-spin" /> : students?.length || 0,
      desc: 'Enregistrés dans la base', 
      icon: Users, 
      colorClass: 'text-schooltrack-action bg-blue-50',
      path: '/students'
    },
    { 
      title: 'Classes', 
      value: loadingClasses ? <Loader2 className="w-5 h-5 animate-spin" /> : classes?.length || 0,
      desc: 'Groupes scolaires', 
      icon: School, 
      colorClass: 'text-schooltrack-primary bg-slate-100',
      path: '/classes'
    },
    { 
      title: 'Voyages Actifs', 
      value: loadingTrips ? <Loader2 className="w-5 h-5 animate-spin" /> : activeTripsCount,
      desc: 'En cours ou planifiés', 
      icon: MapPin, 
      colorClass: 'text-schooltrack-success bg-green-50',
      path: '/trips'
    },
  ];

  const quickLinks = [
    { label: 'Gérer les Bracelets', path: '/tokens', icon: Rss, desc: 'Assignation NFC/QR' },
  ];

  const adminLinks = [
    { label: 'Import CSV', path: '/students/import', icon: Upload, desc: 'Ajout en masse' },
    { label: 'Utilisateurs', path: '/users', icon: UserCog, desc: 'Gestion des accès' },
    { label: 'Audit Logs', path: '/audit', icon: ShieldCheck, desc: 'Historique système' },
  ];

  return (
    <div className="space-y-8 animate-in fade-in duration-700">
      {/* Header section */}
      <div className="flex flex-col gap-2 bg-schooltrack-primary text-white p-8 rounded-3xl shadow-lg shadow-blue-900/10 relative overflow-hidden">
        <div className="absolute top-0 right-0 p-8 opacity-10 pointer-events-none">
          <Activity className="w-48 h-48" />
        </div>
        <div className="relative z-10">
          <h2 className="text-3xl font-bold tracking-tight font-heading">
            Bienvenue, {user?.first_name || user?.email?.split('@')[0]}
          </h2>
          <p className="text-blue-100 text-lg mt-2 max-w-xl leading-relaxed">
            Voici l'état actuel de votre plateforme SchoolTrack. Suivez vos effectifs et gérez vos prochains départs en toute sécurité.
          </p>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        {kpiCards.map((kpi, idx) => (
          <Link key={idx} to={kpi.path} className="group">
            <Card className="h-full border border-slate-200 hover:border-schooltrack-primary/30 hover:shadow-lg hover:shadow-blue-900/5 transition-all duration-300 rounded-2xl bg-white p-6 flex flex-col">
              <div className="flex justify-between items-start mb-4">
                <div className={cn("w-12 h-12 rounded-xl flex items-center justify-center transition-transform group-hover:scale-110", kpi.colorClass)}>
                  <kpi.icon className="w-6 h-6" />
                </div>
                <div className="text-right">
                  <h3 className="text-3xl font-black text-slate-900 font-heading">{kpi.value}</h3>
                </div>
              </div>
              <div className="mt-auto">
                <p className="font-bold text-slate-900 group-hover:text-schooltrack-primary transition-colors">{kpi.title}</p>
                <p className="text-xs text-slate-500 mt-1">{kpi.desc}</p>
              </div>
            </Card>
          </Link>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 pt-4">
        {/* Actions Rapides */}
        <div className="space-y-4">
          <h3 className="text-lg font-bold text-schooltrack-primary font-heading flex items-center gap-2">
            Actions Rapides
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            {quickLinks.map((link, idx) => (
              <Link key={idx} to={link.path} className="group">
                <div className="p-4 bg-white border border-slate-200 rounded-2xl hover:border-schooltrack-action hover:shadow-md transition-all flex items-center gap-4">
                  <div className="w-10 h-10 bg-slate-50 rounded-xl flex items-center justify-center text-slate-500 group-hover:bg-blue-50 group-hover:text-schooltrack-action transition-colors">
                    <link.icon className="w-5 h-5" />
                  </div>
                  <div>
                    <p className="font-bold text-sm text-slate-900 group-hover:text-schooltrack-primary">{link.label}</p>
                    <p className="text-xs text-slate-400">{link.desc}</p>
                  </div>
                </div>
              </Link>
            ))}
          </div>
        </div>

        {/* Administration (Admin only) */}
        {isAdmin && (
          <div className="space-y-4">
            <h3 className="text-lg font-bold text-schooltrack-primary font-heading flex items-center gap-2">
              Administration
            </h3>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {adminLinks.map((link, idx) => (
                <Link key={idx} to={link.path} className="group">
                  <div className="p-4 bg-slate-50 border border-slate-200 rounded-2xl hover:bg-white hover:border-slate-300 hover:shadow-sm transition-all flex items-center gap-4">
                    <div className="w-10 h-10 bg-white rounded-xl shadow-sm flex items-center justify-center text-slate-600 group-hover:text-schooltrack-primary transition-colors border border-slate-100">
                      <link.icon className="w-5 h-5" />
                    </div>
                    <div>
                      <p className="font-bold text-sm text-slate-900">{link.label}</p>
                      <p className="text-xs text-slate-500">{link.desc}</p>
                    </div>
                  </div>
                </Link>
              ))}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
