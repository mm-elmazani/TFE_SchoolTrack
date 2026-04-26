import { useState } from 'react';
import { Outlet, Link, useLocation, useParams, useNavigate } from 'react-router-dom';
import { useAuthStore } from '@/features/auth/store/authStore';
import {
  Users,
  School,
  Map as MapIcon,
  Rss,
  Upload,
  UserCog,
  ShieldCheck,
  LogOut,
  UserCircle,
  Menu,
  ChevronRight,
  LayoutDashboard,
  Package,
  Bell,
  RefreshCw,
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { cn } from '@/lib/utils';

export default function AppScaffold() {
  const { logout, user, getIsAdmin } = useAuthStore();
  const location = useLocation();
  const navigate = useNavigate();
  const { schoolSlug } = useParams();
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
  const isAdmin = getIsAdmin();
  const base = `/${schoolSlug}`;

  const navItems = [
    ...(isAdmin ? [{ label: 'Vue d\'ensemble', path: `${base}/dashboard`, icon: LayoutDashboard }] : []),
    ...(isAdmin ? [{ label: 'Alertes', path: `${base}/alerts`, icon: Bell }] : []),
    { label: 'Élèves', path: `${base}/students`, icon: Users },
    { label: 'Classes', path: `${base}/classes`, icon: School },
    { label: 'Voyages', path: `${base}/trips`, icon: MapIcon },
    { label: 'Bracelets', path: `${base}/tokens`, icon: Rss },
  ];

  const adminItems = [
    { label: 'Import Élèves', path: `${base}/students/import`, icon: Upload },
    { label: 'Stock Bracelets', path: `${base}/tokens/stock`, icon: Package },
    { label: 'Utilisateurs', path: `${base}/users`, icon: UserCog },
    { label: 'Logs d\'Audit', path: `${base}/audit`, icon: ShieldCheck },
    { label: 'Supervision Sync', path: `${base}/sync`, icon: RefreshCw },
  ];

  const isActive = (path: string) =>
    location.pathname === path || (path.length > 1 && location.pathname.startsWith(path));

  const navLinkClass = (path: string) =>
    cn(
      "flex items-center gap-3 px-4 py-3 rounded-xl transition-all duration-200 group",
      isActive(path)
        ? "bg-schooltrack-primary text-white shadow-md shadow-blue-900/20"
        : "text-slate-600 hover:bg-blue-50 hover:text-schooltrack-primary"
    );

  const SidebarContent = () => (
    <div className="flex flex-col h-full bg-white border-r border-slate-200">
      <div className="p-6 flex items-center gap-3 border-b border-slate-50">
        <div className="w-10 h-10 bg-schooltrack-primary rounded-xl flex items-center justify-center text-white shadow-lg">
          <LayoutDashboard className="w-6 h-6" />
        </div>
        <div className="flex flex-col">
          <span className="text-xl font-bold text-schooltrack-primary tracking-tight font-heading">SchoolTrack</span>
          {user?.school_name && (
            <span className="text-xs text-slate-400 font-medium truncate max-w-[140px]">{user.school_name}</span>
          )}
        </div>
      </div>
      
      <nav className="flex-1 p-4 space-y-1 overflow-y-auto">
        <div className="px-4 py-2 text-xs font-semibold text-slate-400 uppercase tracking-widest mb-2">Menu Principal</div>
        {navItems.map((item) => (
          <Link 
            key={item.path} 
            to={item.path} 
            className={navLinkClass(item.path)}
            onClick={() => setIsMobileMenuOpen(false)}
          >
            <item.icon className={cn("w-5 h-5", isActive(item.path) ? "text-white" : "text-slate-400 group-hover:text-schooltrack-primary")} />
            <span className="font-medium">{item.label}</span>
            {isActive(item.path) && <ChevronRight className="ml-auto w-4 h-4" />}
          </Link>
        ))}

        {isAdmin && (
          <div className="pt-6 mt-6 border-t border-slate-100 space-y-1">
            <div className="px-4 py-2 text-xs font-semibold text-slate-400 uppercase tracking-widest mb-2">Administration</div>
            {adminItems.map((item) => (
              <Link 
                key={item.path} 
                to={item.path} 
                className={navLinkClass(item.path)}
                onClick={() => setIsMobileMenuOpen(false)}
              >
                <item.icon className={cn("w-5 h-5", location.pathname.startsWith(item.path) ? "text-white" : "text-slate-400 group-hover:text-schooltrack-primary")} />
                <span className="font-medium">{item.label}</span>
                {location.pathname.startsWith(item.path) && <ChevronRight className="ml-auto w-4 h-4" />}
              </Link>
            ))}
          </div>
        )}
      </nav>

      <div className="p-4 border-t border-slate-100 bg-slate-50/50">
        <Link
          to={`${base}/profile`}
          onClick={() => setIsMobileMenuOpen(false)}
          className="flex items-center gap-3 mb-4 px-2 py-2 -mx-1 rounded-xl hover:bg-blue-50 transition-colors group cursor-pointer"
        >
          <UserCircle className="w-5 h-5 text-slate-400 group-hover:text-schooltrack-primary shrink-0" />
          <div className="min-w-0">
            <p className="text-xs font-medium text-slate-900 truncate group-hover:text-schooltrack-primary">{user?.first_name} {user?.last_name}</p>
            <p className="text-xs text-slate-500 truncate">{user?.email}</p>
            <p className="text-[10px] text-slate-400 uppercase tracking-wider mt-0.5">{user?.role}</p>
          </div>
        </Link>
        <Button 
          variant="destructive"
          onClick={() => { logout(); navigate(`${base}/login`); }}
          className="w-full flex items-center justify-center gap-2 rounded-xl h-11 shadow-sm hover:shadow-md transition-all active:scale-95"
        >
          <LogOut className="w-4 h-4" />
          <span>Déconnexion</span>
        </Button>
      </div>
    </div>
  );

  return (
    <div className="flex h-screen w-full bg-slate-50 text-slate-900 font-sans antialiased overflow-hidden">
      {/* Desktop Sidebar */}
      <aside className="hidden lg:flex w-72 flex-col flex-shrink-0">
        <SidebarContent />
      </aside>

      {/* Mobile Menu Overlay */}
      {isMobileMenuOpen && (
        <div 
          className="fixed inset-0 z-40 bg-slate-900/40 backdrop-blur-sm lg:hidden transition-opacity"
          onClick={() => setIsMobileMenuOpen(false)}
        />
      )}

      {/* Mobile Sidebar */}
      <aside className={cn(
        "fixed inset-y-0 left-0 z-50 w-72 transform lg:hidden transition-transform duration-300 ease-in-out",
        isMobileMenuOpen ? "translate-x-0" : "-translate-x-full"
      )}>
        <SidebarContent />
      </aside>

      {/* Main Content Area */}
      <div className="flex-1 flex flex-col min-w-0 overflow-hidden">
        {/* Header */}
        <header className="h-16 bg-white border-b border-slate-200 flex items-center justify-between px-4 lg:px-8 z-30">
          <div className="flex items-center gap-4">
            <button 
              onClick={() => setIsMobileMenuOpen(true)}
              className="lg:hidden p-2 text-slate-600 hover:bg-slate-100 rounded-lg transition-colors"
            >
              <Menu className="w-6 h-6" />
            </button>
            <h1 className="text-lg font-semibold text-slate-800 hidden sm:block">
              {navItems.find(i => location.pathname.startsWith(i.path))?.label || 
               adminItems.find(i => location.pathname.startsWith(i.path))?.label || 
               'Dashboard'}
            </h1>
          </div>

          <div className="flex items-center gap-4">
            <div className="hidden sm:flex flex-col items-end mr-2 text-right">
              <span className="text-sm font-medium text-slate-700">{user?.first_name} {user?.last_name}</span>
              <span className="text-[10px] text-slate-500 uppercase tracking-tighter">{user?.role}</span>
            </div>
            <Link to={`${base}/profile`} className="w-9 h-9 bg-slate-100 rounded-full border border-slate-200 flex items-center justify-center text-slate-600 font-bold text-xs shadow-inner hover:bg-blue-50 hover:border-schooltrack-primary transition-colors">
              {user?.email?.[0].toUpperCase()}
            </Link>
          </div>
        </header>

        {/* Content */}
        <main className="flex-1 overflow-y-auto p-4 lg:p-8">
          <div className="max-w-7xl mx-auto animate-in fade-in slide-in-from-bottom-2 duration-500">
            <Outlet />
          </div>
        </main>
      </div>
    </div>
  );
}
